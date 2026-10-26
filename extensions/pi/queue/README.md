# Queue Extension for Pi Coding Agent

Sequential task queue: `/queue <task>` schedules a prompt to run **after the
currently executing work fully finishes**, instead of steering it into the
middle of the running turn. Multiple tasks form a FIFO queue and run strictly
one after another.

## Why

Pi has two delivery modes for input typed mid-run:

- **Steering** (plain Enter): injected after the current assistant turn's tool
  calls, before the next LLM call — it can change the agent's direction mid-task.
- **Follow-up** (Alt+Enter): delivered when the agent stops, governed by the
  `followUpMode` setting.

`/queue` is a third option: a user-owned FIFO that fires only on
`agent_settled` — the moment Pi has zero automatic work left (no retries,
compaction, or built-in follow-ups pending). Delivery is sequential and
independent of `followUpMode`, so N queued tasks yield N separate agent runs.

## Commands

| Command | Effect |
|---|---|
| `/queue <task>` | Add a task. Starts immediately if the agent is idle, otherwise waits for settle. |
| `/queue list` | Show pending tasks in FIFO order. |
| `/queue clear` | Drop all pending tasks. |

Notifications:

- `queued (position N) — starts after the current work settles` — accepted while busy
- `▶ queued task started (N remaining)` — task promoted to a fresh agent run

## Example

```
user: <big refactor task>            agent is running...
user: /queue run the test suite
user: /queue summarize the change
      → both queue; refactor finishes → test suite runs → summarize runs
```

## Limitations

- The queue lives in the extension runtime's memory: `/reload`, session
  switch, or restart clears it.
- Aborted runs do **not** promote the next task: `agent_settled` fires with
  `aborted: true`, the queue stays parked, and resumes on the next settle,
  prompt, or `/queue` command.
- If a task fails to start (no model/API key, compaction race), it is put back
  at the front of the queue and you are notified — nothing is silently dropped.
- Built-in follow-ups (Alt+Enter) are part of Pi's automatic work, so they
  are delivered **before** a queued task, per settle-event ordering.
- Task text is sent verbatim: a queued string that begins with `/` is delivered
  to the model as text, not executed as a slash command.

## Install

```bash
./install-extension.sh queue        # symlinks into ~/.pi/agent/extensions/queue
```

Then `/reload` (or restart pi). The extension has no dependencies and no
config — tune behavior in `index.ts` directly; the symlink makes edits take
effect after the next reload.

## Implementation notes

- Registers one command and one event handler; state is a single `string[]`.
- `agent_settled` is the correct hook: `agent_end` can be followed by
  retries/recovery/queued work, so it is not a final-idle signal. The abort
  variant of the event is handled explicitly.
- `dispatching` guards against re-entrant pumps; `ctx.isIdle()` prevents
  racing a run that is already starting.
