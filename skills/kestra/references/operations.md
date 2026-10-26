# Kestra Operations Reference

## Local test instance (when no server is configured)

Docs: `https://kestra.io/docs/installation/docker.md` (append `.md` to any docs URL for clean markdown). Docker image `kestra/kestra` bundles the server + the `kestra` server CLI:

```bash
docker exec -it kestra /app/kestra <command>       # server CLI inside a running container
kestra server standalone --flow-path /path/to/flows  # boot standalone, preload flows at start
docker exec -it kestra /app/kestra flow validate ./flow.yml   # offline validation gate
docker exec -it kestra /app/kestra flow test ./flow.yml input value  # run locally, no deploy
```

Defaults on a fresh OSS standalone: UI/API on `:8080`, admin credentials shown at first boot (or set via config), tenant `main`.

## Secrets, KV, namespace files (where things live)

| Need | Mechanism | Access |
|---|---|---|
| Static secret (API key, webhook URL) | EE: Secrets Manager backends. **OSS: base64 env var `SECRET_<KEY>`** — no encryption at rest, no audit | `{{ secret('KEY') }}` (EE cross-ns: `secret('K', namespace='other')`) |
| Shared/config values, cursors, watermarks | Namespace KV store (typed, TTL, ION-backed) | `{{ kv('KEY') }}`, tasks `io.kestra.plugin.core.kv.{Set,Get,GetKeys,Delete}`, kestractl `kv`, REST, Terraform `kestra_kv` |
| Reusable code/scripts/config artifacts | Namespace files (per-namespace tree, revisions, include/exclude) | `{{ read('dir/file.sql') }}`, task prop `namespaceFiles: {enabled: true}`, `kestractl nsfiles`, `kestra namespace files update` |
| Server-to-server auth with token refresh | EE Credentials | `{{ credential('ID') }}` |

KV cursors pattern for incremental loads: `Set` watermarks after success, `kv('last_run')` (with `default`) at start.

## Maintenance: purge (storage hygiene)

Dedicated tasks (replace legacy `io.kestra.plugin.core.storage.Purge`):
- `io.kestra.plugin.core.execution.PurgeExecutions` — execution records + their storage files (`endDate`, `purgeLog`)
- `io.kestra.plugin.core.log.PurgeLogs` — execution & trigger logs (`endDate`, `logLevels: [DEBUG, TRACE]`, `purgeExecutionLogs`, `purgeNonExecutionLogs`; no-op for unsupported external log stores)
- `io.kestra.plugin.core.kv.PurgeKV` — expired KV keys in a namespace
- `io.kestra.plugin.core.storage.PurgeStorage` — orphaned storage files whose execution rows are gone

Run as a scheduled `system` flow, e.g. retention tiers: all logs −1 month, DEBUG −1 week, TRACE −1 day (`endDate: "{{ now() | dateAdd(-1, 'WEEKS') }}"`).

## Troubleshooting playbook

**Execution failed**
1. `executions get <id> -o json | jq '.tasks[] | {id: .task.id, state: .state.current}'` → failed task.
2. `kestractl logs list <id>` (or `GET /logs/{id}`) → error text; `--level` filters.
3. Live expression values: `executions eval-expression <id> '{{ outputs.x.uri }}'`.
4. Fix → redeploy → `executions restart <id>` (same id, failed only) or `replay` (new id, any start task, outputs cached).

**Execution stuck RUNNING**
- `executions get` → look for PAUSED task (Pause task / `breakpoint`) → `executions resume`.
- Waiting on subflow → check child execution state (`.childExecutions`).
- Worker gone → task never picked up: `kestractl`/UI workers page; kill and restart.

**Executions QUEUED forever**
- Concurrency: Flow page → Concurrency tab / `kestractl flows concurrency-limits`.
- **Namespace/tenant QUEUE + Subflow deadlock**: parents hold slots their queued children need; unrelated flows in scope also queue; does NOT self-resolve. Fix: `executions force-run` a queued child (skips slot), or kill parents ("kill current and subflows"). Prevent: flow-scope limits instead of namespace/tenant QUEUE, or no waiting subflows in limited scope.
- Stuck slot counters after deleting executions: deleting never frees slots — kill running executions first; reset counter on Concurrency Limits page only if still stuck.

**Trigger not firing**
- `triggers list` → state/`locked` field. Trigger stays locked while its previous execution runs unless `allowConcurrent: true`.
- Unlock: `kestractl triggers unlock <ns> <flow> <trigger>`; re-sync schedule: `triggers restart`.
- Timezone gotcha: Schedule `timezone` vs server TZ; verify with `{{ trigger.date }}` in a debug flow.

**Flow won't deploy (validation errors)**
- Read the 400 body (`details` array) — it names the property and reason.
- Verify task type exists on THIS server: `kestractl plugins installed` / `GET /api/v1/main/plugins`; install: `docker exec -it kestra /app/kestra plugins install io.kestra.plugin.<x>:<artifact>:<version>` (restart workers after).
- `kestra flow validate` (server CLI) validates offline without touching the live namespace.

**Auth 401/404 oddities**
- OSS uses basic auth and tenant `main`; EE uses bearer tokens and real tenant ids — wrong tenant surfaces as 404 on flows that exist.
- `kestractl -v` prints masked HTTP requests/responses.

## GitOps / CI-CD

Three supported paths: GitOps (Git = source of truth; Kestra watches a Git repo — EE), CI/CD pipelines (GitHub Actions/GitLab sync via API or CLI), Promote (EE UI).
Pipeline-agnostic pattern (works today with kestractl in any CI job):

```bash
kestractl flows deploy ./flows --override --fail-fast --namespace-prefix "pr-${PR}" --disable-triggers  # preview env
kestractl executions run "pr-${PR}.smoke" smoke-test --wait
kestractl flows deploy ./flows --override --fail-fast   # prod on merge
```

Export/backup: `kestractl flows export-by-query -o file.zip` + `nsfiles` export per namespace; flow sources also via `GET /flows/source`.
Kestra config surface: YAML config + env overrides (`KESTRA_*`, `JAVA_OPTS`); Docker/Compose uses `KESTRA_CONFIGURATION`; docs index: `https://kestra.io/docs/configuration.md`.

## Useful one-liners

```bash
# last 24h failures across a namespace
kestractl executions search --output json --filters 'state=FAILED' ... # or API:
curl -su "$AUTH" -G "$KESTRA/api/v1/main/executions/search" \
  --data-urlencode 'filters[namespace][PREFIX]=company' \
  --data-urlencode 'filters[state][EQUALS]=FAILED' \
  --data-urlencode 'filters[startDate][GREATER_THAN_OR_EQUAL_TO]=2026-10-23T00:00:00Z' \
  | jq -r '.results[] | [.id, .namespace, .flowId, .state.current] | @tsv'

# flows containing a deprecated task type
kestractl flows list-deprecated
# find all flows calling an endpoint / table
kestractl flows search-by-source company 's3://bucket'
# kill everything running in a namespace
kestractl executions kill-by-query --namespace company.leak --state RUNNING
```
