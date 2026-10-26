# Kestra REST API Reference

Base: `https://<host>/api/v1/{tenant}/...` — tenant is `main` on Open Source, the tenant id on EE/Cloud.
Auth: HTTP basic (`-u user:pass`) on OSS; `Authorization: Bearer <api-token>` on EE/Cloud.
Interactive docs on any instance: `https://<host>/api` (Swagger). Full spec: `https://kestra.io/kestra.yml` (v2) / `https://kestra.io/kestra-ee.yml`.
216 operations; complete machine-readable path list obtainable from the spec. Most-used groups below.

Set `export KESTRA=http://localhost:8080 AUTH='admin:admin'` once, then:

## Flows

```bash
# create/update from YAML source (PUT = update with tenant+ns+id)
curl -s -u "$AUTH" -X POST "$KESTRA/api/v1/main/flows" -H 'Content-Type: application/yaml' --data-binary @flow.yml
curl -s -u "$AUTH" -X PUT  "$KESTRA/api/v1/main/flows/company.team/my-flow" -H 'Content-Type: application/yaml' --data-binary @flow.yml
curl -s -u "$AUTH" "$KESTRA/api/v1/main/flows/company.team/my-flow"            # get
curl -s -u "$AUTH" "$KESTRA/api/v1/main/flows/company.team/my-flow/revisions"  # revision history
curl -s -u "$AUTH" -X POST "$KESTRA/api/v1/main/flows/validate" -H 'Content-Type: application/yaml' --data-binary @flow.yml
curl -s -u "$AUTH" "$KESTRA/api/v1/main/flows/search?filters[namespace][PREFIX]=company"
curl -s -u "$AUTH" "$KESTRA/api/v1/main/flows/source"                          # all sources (bulk audit)
curl -s -u "$AUTH" -X POST "$KESTRA/api/v1/main/flows/bulk" -H 'Content-Type: application/x-yaml' --data-binary @multi.yml
curl -s -u "$AUTH" -X POST "$KESTRA/api/v1/main/flows/export/by-ids" -H 'Content-Type: application/json' \
  -d '[{"namespace":"company.team","id":"my-flow"}]' -o flows.zip
# bulk ops: /flows/enable|disable|delete/{by-ids,by-query} ; dependency graph: /flows/{ns}/{id}/graph
```

## Executions

```bash
# trigger; inputs as JSON body. Query params: wait=true, waitUntil=<STATE>, labels[k]=v
curl -s -u "$AUTH" -X POST "$KESTRA/api/v1/main/executions/company.team/my-flow?wait=true" \
  -H 'Content-Type: application/json' -d '{"env":"prod","dry_run":true}'
curl -s -u "$AUTH" "$KESTRA/api/v1/main/executions/<execId>"                   # get (state, tasks[].state)
curl -s -u "$AUTH" -H 'Accept: application/x-yaml' "$KESTRA/api/v1/main/executions/<execId>"
curl -s -N -u "$AUTH" "$KESTRA/api/v1/main/executions/<execId>/follow"          # SSE until terminal
curl -s -u "$AUTH" -X DELETE "$KESTRA/api/v1/main/executions/<execId>/actions/kill"

# single-execution actions (POST unless noted)
#   actions/restart          rerun failed tasks, same execution
#   actions/replay[?taskRunId=..&newExecutionId=..]   new execution from any task
#   actions/pause | actions/resume (validate inputs first: actions/resume/validate)
#   actions/force-run | actions/unqueue | actions/change-status | actions/state (taskrun)
#   actions/eval             '?expression={{ outputs.x.uri }}'  (also /actions/eval/{taskRunId})
#   actions/labels           set labels on terminated execution
# bulk: /executions/{restart,replay,pause,resume,kill,force-run,unqueue,change-status,labels}/{by-ids,by-query}
#   by-ids body: ["id1","id2"] ; by-query: filters[...] query params
# search: GET /executions/search?filters[state][IN]=RUNNING,QUEUED&filters[namespace][PREFIX]=company
#         GET /executions?filters[flowId][EQUALS]=my-flow&filters[namespace][EQUALS]=company.team  (per-flow)
# logs:   GET /logs/{execId}?tokens=...  | follow: /logs/{execId}/follow (SSE) | /logs/search
# outputs: GET /outputs/executions/{execId} ; stored files: /executions/{execId}/file?name=...
# webhooks: GET|POST|PUT /executions/webhook/{ns}/{flowId}/{key}
```

## Triggers & backfills

```bash
curl -s -u "$AUTH" "$KESTRA/api/v1/main/triggers/search?filters[namespace][EQUALS]=company.team"
curl -s -u "$AUTH" -X PUT "$KESTRA/api/v1/main/triggers/set-disabled" \
  -H 'Content-Type: application/json' \
  -d '{"slugs":["company.team:my-flow:schedule"],"disabled":true}'
curl -s -u "$AUTH" -X POST "$KESTRA/api/v1/main/triggers/company.team/my-flow/schedule/restart"
curl -s -u "$AUTH" -X POST "$KESTRA/api/v1/main/triggers/company.team/my-flow/schedule/unlock"
# backfill history (start/end between which the schedule re-runs):
curl -s -u "$AUTH" -X PUT "$KESTRA/api/v1/main/triggers/backfill/create" \
  -H 'Content-Type: application/json' \
  -d '{"slugs":["company.team:my-flow:schedule"],"start":"2026-10-01T00:00:00Z","end":"2026-10-20T00:00:00Z"}'
# also: backfill/{pause,unpause,delete} (+ /by-triggers, /by-query variants)
```

## Query filters (all list & by-query endpoints)

Syntax `filters[<field>][<OP>]=<value>`; multiple params AND-combined.
Operators: `EQUALS NOT_EQUALS IN NOT_IN CONTAINS NOT_CONTAINS STARTS_WITH ENDS_WITH PREFIX REGEX GREATER_THAN GREATER_THAN_OR_EQUAL_TO LESS_THAN LESS_THAN_OR_EQUAL_TO IS_NULL IS_NOT_NULL`.

- `PREFIX` matches dot-segments: `company` matches `company.team[.prod]`, not `company.t`.
- Labels: key in 3rd bracket — `filters[labels][EQUALS][env]=prod` (never `env:prod`).
- OR groups: `filters[or][0][namespace][EQUALS]=a&filters[or][0][flowId][EQUALS]=b&filters[or][1][namespace][EQUALS]=c`; nestable (`filters[and][0][or][0][...]`), max depth 3 / width 20.
- Executions fields: `namespace flowId state labels startDate endDate scope kind childFilter parentId taskId triggerId triggerExecutionId q`.
- Flows fields: `namespace flowId labels scope q`. Triggers: `... triggerId triggerState workerId source locked lastTriggeredDate nextExecutionDate`.
- Bulk by-query endpoints REJECT flat legacy params (`?namespace=x` → 400 invalid-query-filters).

## KV store, namespace files, plugins, namespaces

```bash
# KV (values JSON-encoded; types: STRING NUMBER BOOLEAN DATETIME DATE DURATION JSON)
curl -s -u "$AUTH" -X PUT "$KESTRA/api/v1/main/namespaces/company.team/kv/my_key" \
  -H 'Content-Type: application/json' -d '"Hello World"'
curl -s -u "$AUTH" "$KESTRA/api/v1/main/namespaces/company.team/kv/my_key"
curl -s -u "$AUTH" "$KESTRA/api/v1/main/namespaces/company.team/kv/inheritance"     # incl. parent namespaces
curl -s -u "$AUTH" -X DELETE "$KESTRA/api/v1/main/namespaces/company.team/kv/my_key" # returns true/false
# namespace files
curl -s -u "$AUTH" -X POST "$KESTRA/api/v1/main/namespaces/company.team/files/sub/f.txt" \
  -H 'Content-Type: text/plain' --data-binary @f.txt
curl -s -u "$AUTH" "$KESTRA/api/v1/main/namespaces/company.team/files/sub/f.txt"
curl -s -u "$AUTH" "$KESTRA/api/v1/main/namespaces/company.team/files/directory?path=/sub"
curl -s -u "$AUTH" "$KESTRA/api/v1/main/namespaces/company.team/files/export" -o nsfiles.zip
# plugins & schemas
curl -s -u "$AUTH" "$KESTRA/api/v1/main/plugins"                                  # installed on server
curl -s -u "$AUTH" "$KESTRA/api/v1/main/plugins/schemas/io.kestra.plugin.core.log.Log"
curl -s -u "$AUTH" -X POST "$KESTRA/api/v1/main/plugins/auto-install/detect" -H 'Content-Type: application/yaml' --data-binary @flow.yml
```

## Response conventions

- Errors: JSON with `message` + `details` array (validation), plus `invalid-query-filters` error type for bad filters.
- List endpoints return JSON arrays; paginated ones accept `?size=&from=` or `searchAfter` cursor params.
- Timestamps ISO 8601 UTC. Durations ISO 8601 (`PT15M`).
- Always check the response body for proof of success, not just HTTP status; parse with `jq`.
