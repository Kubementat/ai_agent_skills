---
name: kestra
description: |
  Use Kestra like a pro: deploy, trigger, monitor, and debug workflows via kestractl CLI and REST API.
  Covers flow YAML authoring (tasks, flowables, triggers, retries, errors, concurrency, subflows), Pebble expressions,
  KV store, namespace files, secrets, and bulk operations.
  Triggers: kestra, flow, workflow orchestration, kestractl, executions, backfill, namespace files, kv store, Pebble.
---

# Kestra Skill

Operational skill for running Kestra (v2.x, also works against 1.x) from the CLI and API: deploying flows, triggering and watching executions, debugging failures, and authoring production-grade flow YAML.

Kestra ships two CLIs: **kestractl** (standalone API client — install it, use it for everything remote) and **kestra** (server CLI, only available inside the server container/host — validate/test/validate-offline, plugins, sys).

## When to Use

- Deploy, update, import/export, enable/disable flows
- Trigger executions (manual, webhook), wait for results, read logs
- Debug failed/stuck/queued executions; restart, replay, kill, pause/resume
- Manage triggers (backfills, enable/disable, restart, unlock), namespaces, namespace files, KV store, secrets
- Author or review flow YAML: tasks, flowables (DAG/Loop/Parallel/Subflow…), retries, error handlers, concurrency
- Script anything against the Kestra REST API with curl

Don't use for: installing/operating the Kestra server itself beyond pointing at docs.

## Prerequisites

kestractl (one-time install, then it's persistent):

```bash
curl -fsSL https://raw.githubusercontent.com/kestra-io/kestractl/main/install-scripts/install.sh | bash
# installs to ~/.local/bin (2.x client; use VERSION=1 for a Kestra 1.x server)
kestractl config add default http://localhost:8080 main --username admin --password admin --default
kestractl config show && kestractl server info   # prove connectivity
```

- OSS server: basic auth (`--username/--password`), tenant is `main`. EE/Cloud: API token (`--token`), real tenant name.
- Auth sources, in precedence order: CLI flags > env vars (`KESTRACTL_HOST`, `KESTRACTL_TENANT`, `KESTRACTL_TOKEN` or `KESTRACTL_USERNAME`/`KESTRACTL_PASSWORD`, `KESTRACTL_OUTPUT=json`) > `~/.kestractl/config.yaml` contexts.
- Multiple servers: `kestractl config add <name> <url> <tenant> ...` then `kestractl config use <name>`.
- Never put credentials in flow YAML: use `{{ secret('KEY') }}` (OSS reads base64 env vars `SECRET_<KEY>`).
- If no server is configured, ask the user for the URL + credentials or suggest the local Docker quickstart (see references/operations.md).

## Quick Reference

Every command supports `-o json` for parsing. Full command trees: `references/cli.md`. API recipes: `references/api.md`. Flow YAML: `references/flow-authoring.md`. Troubleshooting: `references/operations.md`.

```bash
# Flows
kestractl flows deploy ./flow.yml --override            # deploy/update one flow
kestractl flows deploy ./flows-dir --override --fail-fast
kestractl flows get <ns> <flow-id> | list-by-namespace <ns> | revisions <ns> <flow-id>
kestractl flows search-by-source <ns> <pattern> ; kestractl flows list-deprecated

# Executions
kestractl executions run <ns> <flow-id> --input k=v --wait
kestractl executions get <exec-id> -o json
kestractl logs list <exec-id>
kestractl executions restart <exec-id>        # rerun failed tasks, same execution
kestractl executions replay <exec-id>         # new execution (optionally from a task)
kestractl executions kill|pause|resume|force-run <exec-id>
kestractl executions search-by-flow <ns> <flow-id>

# Triggers / data
kestractl triggers list --namespace <ns> ; kestractl triggers restart|unlock <ns> <flow> <trigger>
kestractl kv set|get|list|delete ... ; kestractl nsfiles upload|list|delete ...
```

```bash
# API (same auth for all: basic) — interactive docs at https://<host>/api
curl -s -u admin:admin "$KESTRA_URL/api/v1/main/flows/search" \
  --data-urlencode "filters[namespace][PREFIX]=company" -G
curl -s -u admin:admin -X POST "$KESTRA_URL/api/v1/main/executions/<ns>/<flow-id>?wait=true" \
  -H 'Content-Type: application/json' -d '{"myInput":"value"}'
```

## Procedures

### Deploy a flow safely
1. Validate locally (needs server CLI inside the container: `docker exec -it kestra /app/kestra flow validate ./flow.yml`; otherwise the deploy response itself reports validation errors).
2. `kestractl flows deploy ./flow.yml --override` — completion criterion: exit 0 and `kestractl flows get <ns> <id>` shows the new revision.
3. Smoke test: `kestractl executions run <ns> <id> --wait` and check final state.

### Run and watch an execution
1. `kestractl executions run <ns> <id> --input k=v -o json` → capture `.id`.
2. `--wait` blocks until terminal state; otherwise poll `executions get <id>` `.state`.
3. On failure: `kestractl logs list <id>` — criterion: you can name the failed task id and error message.

### Debug a failed execution
1. `kestractl executions get <id> -o json` → find taskRun with state FAILED (`tasks[].state.current`).
2. `kestractl logs list <id>` (add task filter) → root cause from the task log lines.
3. Want live values? `kestractl executions eval-expression <id> "{{ outputs.some_task.uri }}"`.
4. Fix + redeploy, then `executions restart <id>` (same execution, only failed tasks rerun) or `executions replay` (fresh execution id).

### Backfill a schedule
`kestractl triggers` + API `PUT /api/v1/main/triggers/backfill/create` with `start`/`end`/`slugs` — see references/api.md. Unpause/pause/delete via `triggers/backfill/{pause,unpause,delete}`.

### Author a new flow
Use the skeleton and task catalog in `references/flow-authoring.md`. Before inventing a task type, look it up: plugin docs at `https://kestra.io/plugins`, JSON schema via `GET /api/v1/plugins/schemas/<type>`, or `kestractl plugins` commands. Never guess fully-qualified `io.kestra.plugin.*` class names.

## Pitfalls

- **Execution context ≈ 1 MB.** Outputs are serialized on every state change. For big data use `store: true` / file URIs / internal storage, never `fetch` large results into outputs. Flows >100 tasks per execution degrade badly — split with Subflows.
- `Loop` over a list of objects: `item.value` is a JSON **string** — use `{{ fromJson(item.value).field }}`.
- `Parallel`/`DAG` siblings cannot read each other's outputs (only tasks after the block).
- `WorkingDirectory` rejects flowable children (Parallel/Loop) at save time.
- **Concurrency deadlock:** namespace/tenant limit with `behavior: QUEUE` + Subflows waiting in the same scope deadlocks silently. Fix: Force run a queued child, or Kill parent ("kill current and subflows"), or move the limit to flow scope. Deleting executions does NOT free stuck slots — kill them.
- Bulk by-query endpoints require `filters[...]` bracket syntax; flat `?namespace=x` params are rejected 400. Label filters need the key in a third bracket: `filters[labels][EQUALS][env]=prod`.
- Trigger locks while its execution runs (no overlap) unless `allowConcurrent: true`.
- OSS secrets are base64 env vars (`SECRET_*`) — no encryption at rest; don't imply a secret store exists.
- `retry.interval` must be < `retry.maxDuration` or retries never fire. Durations are ISO 8601 (`PT15M`, `PT0.25S`).
- Tenant path segment: OSS is always `main`; wrong tenant → 404s that look like missing flows.
- kestractl has no `--version` flag; use `kestractl version`. `~/.local/bin` must be on PATH.

## Doc Discovery (don't guess — fetch)

- Any docs page as markdown: append `.md` → `https://kestra.io/docs/<path>.md`
- Docs index: `https://kestra.io/docs/llms.txt` · agent guide: `https://kestra.io/docs/ai-tools/docs-for-agents.md`
- Full OpenAPI spec (v2): `https://kestra.io/kestra.yml` · live instance: `https://<host>/api` (Swagger) + `GET /api/v1/main/flows` etc.
- Plugin/task schemas: `https://api.kestra.io/v1/plugins/schemas/flow`, `GET /api/v1/plugins/schemas/<type>`

## Verification

- `kestractl config show` points at the intended server; `kestractl server info` responds.
- A skill-invoked deploy is proven by `kestractl flows revisions <ns> <id>` showing a new revision AND a passing `executions run --wait`.
- API calls are proven by parsing the JSON response, not the HTTP 2xx alone.
