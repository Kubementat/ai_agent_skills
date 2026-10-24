# Kestra Flow Authoring Reference (v2)

## Skeleton

```yaml
id: my_flow                      # required, unique within namespace
namespace: company.team          # required, dot-separated hierarchy
description: |
  What this flow does. Markdown allowed.
revision: 1                      # optional pin; default = latest

labels:
  team: data

inputs:
  - id: env
    type: STRING
    required: true
    defaults: dev
    validators:
      - type: EQUALS
        value: [dev, staging, prod]   # or ENUM-style validation per type
  - id: run_date
    type: DATETIME
    defaults: "{{ trigger.date }}"

variables:
  tmp_table: "tmp_{{ execution.id }}"   # lazily evaluated, flow-wide

concurrency:
  limit: 2
  behavior: QUEUE            # QUEUE | CANCEL | FAIL

tasks:
  - id: hello
    type: io.kestra.plugin.core.log.Log
    message: "hello {{ inputs.env }}"

errors:                      # runs (sequentially) when any task/flow fails
  - id: alert
    type: io.kestra.plugin.core.log.Log
    message: "FAILED {{ flow.id }} task={{ tasksWithState('FAILED')[0]['taskId'] }}"

triggers:
  - id: nightly
    type: io.kestra.plugin.core.trigger.Schedule
    cron: "0 3 * * *"
    timezone: Europe/Berlin
```

Other top-level keys: `pluginDefaults` (per-type property defaults), `disabled: true`, `flow-controls` via `afterExecution` (runs after terminal state; `runIf` on final state).

## Runnable task essentials

Every runnable task accepts: `id`, `type` (fully-qualified `io.kestra.plugin...` — look it up, never guess), `disabled`, `timeout: PT10M`, `retry: {...}`, `allowFailure: true`, `allowWarning: true`, `workerId`/`workerGroup` (EE), `logToFile`.

Common core types:
- `io.kestra.plugin.core.log.Log` — `message`, `level`
- `io.kestra.plugin.core.flow.Sleep` — `duration`
- `io.kestra.plugin.core.output.OutputValues` — `values: {k: v}` → `outputs.<id>.values.k`
- `io.kestra.plugin.core.execution.Fail` — `errorMessage`, `condition`
- `io.kestra.plugin.core.http.Request` — `uri`, `method`, `options.headers`, `options.body` → `outputs.<id>.code/.body`
- `io.kestra.plugin.scripts.shell.Commands` / `python.Script` / `node.Script` — `commands|script`, `beforeCommands`, `env`, `inputFiles`, `outputFiles`, `taskRunner: {type: io.kestra.plugin.core.runner.Process}` (OSS local runner) or docker runner.

Outputs: `{{ outputs.<task_id>.<prop> }}`. Task emits custom outputs from scripts via `::{"outputs": {"k": "v"}}::` stdout marker. Large data: set `store: true` where available → use `.uri` (then `.value` is gone; use `read()`/`fromJson()` on the URI). File reads: `{{ read('file.txt') }}`, `{{ readLines(outputs.x.uri) }}`, `{{ fromJson(str).field }}`.

## Flowables (control flow)

All are `io.kestra.plugin.core.flow.<Name>`:

- **Sequential** — children in order; siblings' outputs visible to later children. Has `errors`/`finally` slots.
- **Parallel** — children concurrently; `concurrent: N` cap; `onChildFailure: FAIL|CANCEL|CONTINUE`. No sibling outputs inside the block.
- **Dag** — `tasks: [{task: {...}, dependsOn: [id...]}, ...]`; independent tasks run in parallel; `concurrent: N`.
- **Switch** — `value: "{{ ... }}"`, `cases: {caseName: [tasks]}`, `default:`.
- **If** — `condition: "{{ ... }}"`, `then: [...]`, `else: [...]`. Falsy: `0, -0, null, ''`.
- **Loop** — `values:` list | JSON array string | map | file URI (one iter/line); child vars `{{ item.index }}`, `{{ item.value }}`, `{{ item.key }}`, `{{ item.parent.value }}`, `{{ item.parents[n].value }}`. Objects in lists arrive as JSON strings → `fromJson(item.value).x`. `concurrencyLimit: 0` (default: all parallel). Per-iteration `outputs:` list. Each iteration is an isolated sub-execution.
- **LoopUntil** — `condition` (sees child outputs of latest run), `checkFrequency: {interval, maxIterations, maxDuration}`, `failOnMaxReached`; after completion `outputs.<id>.iterationCount`.
- **AllowFailure** — children may fail; block → `WARNING`, execution continues, final state `WARNING`.
- **Subflow** — `namespace`, `flowId` (required), `inputs: {...}`, `wait: true`, `transmitFailed: true`, `revision`, `inheritLabels`, `scheduleDate`. Outputs: `outputs.<id>.executionId`, `.state`, `.outputs.<key>` (subflow must declare `outputs:`). `wait: false` = fire-and-forget.
- **WorkingDirectory** — children run on same worker, same dir (`{{ workingDir }}`); supports `cache: {patterns: [...], ttl: PT1H}` and `namespaceFiles: {enabled: true, include/exclude}`. No flowable children allowed.
- **Pause** — waits for resume (UI Gantt or API); `pauseDuration: PT5M`, `behavior: RESUME|WARN|CANCEL|FAIL`, `onResume: [inputs]` → `{{ outputs.<id>.onResume.<input> }}`.

## Retries

```yaml
  retry:
    type: constant        # constant | exponential | random
    maxAttempts: 5        # includes first attempt
    interval: PT15M       # constant; exponential: interval+delayFactor(2)+maxInterval; random: minInterval/maxInterval
    maxDuration: PT1H     # total across attempts; must be > interval
    warningOnWarning: true
    behavior: RETRY_FAILED_TASK   # on flowables; RETRY_FLOWABLE = rerun whole block (e.g. token refresh)
```

Flow-level `retry:` block: `behavior: CREATE_NEW_EXECUTION | RETRY_FAILED_TASK`. `timeout` = per attempt; `retry.maxDuration` = across attempts. `{{ taskrun.attemptsCount }}` in task logic. Retry whole group as fresh execution = Subflow + retry.

## Errors & failure semantics

- `errors:` (flow level or on flowables) — runs after failure; `tasksWithState('FAILED')` gives failed task infos.
- `allowFailure: true` on a task → downstream continues, execution ends `WARNING`. `allowWarning: true` → ends `SUCCESS`.
- `afterExecution` top-level — post-terminal-state hook, `runIf: "{{ execution.state.current == 'FAILED' }}"` style.
- Manual recovery: **Restart** (failed tasks, same execution) / **Replay** (new execution from any task, cached outputs reused) / automatic **Retry** only.

## Triggers

```yaml
triggers:
  - id: schedule
    type: io.kestra.plugin.core.trigger.Schedule
    cron: "*/15 * * * *"
    withSeconds: false            # true = 6-field cron
    timezone: Europe/Berlin
    backfill: {start: "2026-01-01T00:00:00Z", end: null, every: PT1H}
    allowConcurrent: false        # trigger locked while its execution runs
    # available in flow: {{ trigger.date }}, {{ trigger.nextDate }}, {{ trigger.backfill }}, {{ trigger.cron }}

  - id: on_push
    type: io.kestra.plugin.core.trigger.Webhook
    key: some-secret-key          # URL: /api/v1/main/executions/<ns>/<flow>/<key>
    conditions: [...]             # optional EE-style filters; body -> {{ trigger.payload }}

  - id: after_upstream
    type: io.kestra.plugin.core.trigger.Flow
    dependsOn:
      - namespace: company.release
        flowId: parent
        states: [SUCCESS]         # default: all terminal + PAUSED
    # {{ triggerExecution.id }}, {{ trigger.flow }} available downstream
```

Also: `io.kestra.plugin.core.trigger.*` polling triggers via plugins (S3, Postgres listener, etc. — look up in plugin registry). Backfill lifecycle via API `PUT /triggers/backfill/{create,pause,unpause}` and `.../delete`.

## Inputs

Types: `STRING INT FLOAT BOOLEAN DATETIME DATE DURATION FILE JSON ARRAY SECRET`.
Properties: `required`, `defaults`, `description`, `enabled`, `validators` (type-specific: MIN/MAX, EQUALS/PATTERN, FORMAT, MIN_LENGTH/MAX_LENGTH...). `FILE` inputs are stored as internal storage URIs — pass file paths via CLI/API multipart. `SECRET` inputs mask values at rest.
Access: `{{ inputs.<id> }}`.

## Pebble expressions (essentials)

- Context: `{{ inputs.x }}`, `{{ outputs.<taskId>.<prop> }}`, `{{ vars.x }}`, `{{ task.id }}`, `{{ taskrun.id }}`, `{{ taskrun.attemptsCount }}`, `{{ execution.id }}`, `{{ flow.id }}`, `{{ flow.namespace }}`, `{{ trigger.date }}`, `{{ labels.env }}`, `{{ workingDir }}`, `{{ item.* }}` (in Loop), `{{ kv('KEY') }}`, `{{ secret('KEY') }}` (EE: `secret('K', namespace='other.ns')`).
- Functions: `now()`, `today()`, `date(...)`, `formatDate(x,'yyyy-MM-dd')`, `dateFormat`, `dateAdd`, `read(uri)`, `readLines(uri)`, `fromJson(str)`, `toJson(x)`, `toIon`, `render(str)`, `decrypt`, `credential('ID')` (EE), `tasksWithState('FAILED')`.
- Filters: `| default('x')`, `| replace('a','b')`, `| upper | lower`, `| jsonPath('$.a.b')`, `| number`, `| slugify`, `| trim`, `| first`, `| map(...)`, ternary `{{ c ? a : b }}`.
- Conditional property: use expressions as whole property values (`message: "{{ ... }}"`), not string concatenation inside YAML scalars with reserved chars.
- Debug expressions live: API `POST /executions/{id}/actions/eval` or `kestractl executions eval-expression`.

## Design rules (performance & reliability)

1. Execution context is serialized per state transition, ~1 MB hard-ish limit: never `fetch`/output bulk rows — use `store: true`, internal storage URIs, or intermediate files.
2. <100 tasks per execution; split with Subflows (isolated executions).
3. `Parallel`/`Dag` for independent branches; cap `concurrent` to protect external rate limits.
4. Always set `timeout` on long/uncertain tasks; add `retry` on flaky I/O (exponential for remote APIs).
5. Idempotency: executions can be restarted/replayed — make tasks re-runnable (upserts, deterministic targets with `{{ execution.id }}` suffixes).
6. Cross-flow deps = Flow triggers (`dependsOn`), not nested subflow pyramids.
7. Secrets via `secret()`; shared config via KV store (`kv()`); reusable code/scripts via namespace files (`read()`, `namespaceFiles.enabled: true`).
8. DRY with `pluginDefaults`, `variables`, Subflows, and (EE) blueprints/reusable modules.
