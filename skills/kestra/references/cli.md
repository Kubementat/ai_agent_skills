# Kestra CLI Reference

Two CLIs:
- **kestractl** — standalone API client (curl replacement). Install once, works against any server (build targets Kestra 2.x, best-effort 1.x).
- **kestra** (server CLI) — the Kestra executable itself; only available on the server host/container (`docker exec -it kestra /app/kestra ...` or standalone `./kestra-VERSION`). Use for offline validate/test, server-side plugin install, DB maintenance.

## kestractl

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/kestra-io/kestractl/main/install-scripts/install.sh | bash
# -> ~/.local/bin/kestractl (ensure on PATH). VERSION=1 ... | bash for Kestra 1.x servers
kestractl version    # there is no --version flag
```

### Auth & contexts

```bash
# OSS (basic auth; tenant = main)
kestractl config add default http://localhost:8080 main --username admin --password admin --default
# EE / Cloud (API token)
kestractl config add prod https://<tenant>.kestra.cloud <tenant> --token ***
kestractl config show | use prod | remove prod
```

Env overrides (prefix `KESTRACTL_`): `HOST`, `TENANT`, `TOKEN`, `USERNAME`, `PASSWORD`, `OUTPUT=json`.
Precedence: flags (`--host --tenant --token --username --password --header K:V -v`) > env > config file (`~/.kestractl/config.yaml`). `-v` prints masked HTTP requests — use when debugging auth.

### Command groups

`apps, assets, bindings, blueprints, config, dashboards, executions, flows, groups, invitations, kv, logs, namespaces, nsfiles, plugins, reusable-inputs, roles, secrets, server, service-accounts, tenants, test-suites, triggers, users, workers` (EE-only: apps, assets, dashboards, test-suites, reusable-inputs, tenants, IAM groups/roles/users/...).

### flows

```bash
kestractl flows deploy <file|dir> [--override] [--fail-fast] [--recursive=false] \
    [--namespace <target>] [--namespace-prefix <pfx>] [--disable-triggers]
kestractl flows bulk-update <multi-doc.yml> | namespace-sync <file>
kestractl flows create|update <file> ; flows delete <ns> <id> | delete-bulk | delete-by-query
kestractl flows list | list-by-namespace <ns> | search [filters] | search-by-source <ns> <q>
kestractl flows get <ns> <id> ; flows task <ns> <id> <task-id> ; flows revisions <ns> <id>
kestractl flows graph <ns> <id> | generate-graph-from-source <file> | dependencies <ns> <id>
kestractl flows enable|disable <ns> <id...> | enable-by-query | disable-by-query
kestractl flows export|export-by-query | import <file.zip|yml>
kestractl flows concurrency-limits | update-concurrency <ns> <id> --limit N
kestractl flows list-deprecated ; flows expressions <file> ; flows usage-report
```

`--namespace-prefix` copies flows into per-branch/PR namespaces; internal references (Subflow targets, Flow triggers, nsfiles, KV) are NOT rewritten.

### executions

```bash
kestractl executions run <ns> <flow-id> [--input k=v ...] [--wait] [--label k=v]
#   array inputs: --input 'tags=["a","b"]' ; aliases: trigger, execute
kestractl executions trigger-webhook <ns> <flow-id> <key> [--data ...]
kestractl executions get <id> | list | search-by-flow <ns> <id> | latest <ns/id...>
kestractl executions logs via: kestractl logs list <id> [--task <task-id>]
kestractl executions kill|pause|resume|force-run <id>  (+ -bulk / -by-query variants)
kestractl executions restart <id>          # rerun failed tasks, same execution id
kestractl executions replay <id> [--task-run-id ...]   # new execution id
kestractl executions replay-with-inputs <id> ...       # new execution + input overrides
kestractl executions change-status <id> --state <STATE>   # careful: manual state change
kestractl executions set-labels <id> --label env=prod     # terminated executions only
kestractl executions eval-expression <id> '{{ outputs.x.uri }}' [--task-run-id ...]
kestractl executions download-file <id> ; file-metadata <id>
kestractl executions delete|delete-bulk|delete-by-query   # does NOT free concurrency slots!
```

Execution states: `CREATED SUBMITTED RUNNING PAUSED RESTARTED KILLING SUCCESS WARNING FAILED KILLED CANCELLED QUEUED RETRYING RETRIED SKIPPED BREAKPOINT RESUBMITTED`.

### triggers

```bash
kestractl triggers list [--namespace <ns>] | delete <ns> <flow> <trigger>
kestractl triggers restart <ns> <flow> <trigger>   # re-evaluates from now (Schedule)
kestractl triggers unlock <ns> <flow> <trigger>    # stuck trigger lock
# enable/disable + backfills via API (see api.md): PUT /triggers/set-disabled, PUT /triggers/backfill/*
```

### namespaces, nsfiles, kv, secrets

```bash
kestractl namespaces create|list|delete|get ...
kestractl nsfiles upload <ns> <local-path> [--destination /dir] | list | delete | revisions ...
kestractl kv set <ns> <key> <value> [--type STRING] [--expiration 1d] | get | list [--prefix] | delete
kestractl secrets set|list|delete ...   # EE only for real store; OSS secrets = SECRET_* env vars
```

### plugins, server, workers

```bash
kestractl plugins list <kestra-version>     # public compatibility catalog
kestractl plugins get <group:artifact:version> ; plugins download [version] [--directory]
kestractl plugins installed                 # what the connected server actually runs
kestractl plugins ... --from-config         # bootstrap core plugins for standalone workers
kestractl server info | diagnostics
kestractl workers registration-tokens generate   # EE remote workers
```

## kestra (server CLI)

Run inside the server image: `docker exec -it kestra /app/kestra <cmd>` or `./kestra-VERSION <cmd>`. Global flags: `-c/--config`, `-p/--plugins`, `-v/-vv`, `--log-level`. API-targeting flags for remote commands: `--server http://host:8080`, `--user user:pass`, `--tenant`, `--api-token`, `--headers k=v`.

```bash
kestra flow validate /path/flow.yml           # offline validation — best pre-deploy gate
kestra flow test /path/flow.yml input1 val1   # run locally without deploying (file inputs: absolute paths)
kestra flow dot /path/flow.yml                # Graphviz DOT of topology
kestra flow update <file> <ns> <id> | updates <dir> [--delete] [--namespace <ns>]
kestra flow create <file> | delete <ns> <id> | export [--namespace <ns>] <dir>
kestra namespace files update <ns> <localdir> / [--delete]
kestra namespace kv update <ns> <key> <value> [-e 1d] [-t STRING] [-f]
kestra plugins install io.kestra.plugin.jdbc:mysql:1.2.3 [--repositories ...] | uninstall | list
kestra configs properties                     # effective config
kestra sys purge ...                          # delete executions/logs/metrics older than date — see operations.md
kestra migrate plan [--sql] | run | unlock    # DB migrations (EE: run manually before 2.0 start)
kestra server standalone --flow-path /path/to/flows   # start all-in-one, preload flows
```
