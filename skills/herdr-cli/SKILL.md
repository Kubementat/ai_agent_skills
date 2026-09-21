---
name: herdr-cli
description: Expert guide for herdr, the terminal workspace manager for AI coding agents.
disable-model-invocation: false
---

# herdr — Terminal Workspace Manager for AI Agents

herdr is a terminal workspace manager that hosts and orchestrates AI coding agents (pi, Claude Code, Codex, Gemini, Cursor, Devin, and 15+ more) in persistent terminal sessions behind a UNIX socket.

## Primary Workflow — Launching and Using an Agent

__ATTENTION: The main usage scenario is implemented in helper scripts: `scripts/run-pi-herdr.sh` (pi), `scripts/run-claude-herdr.sh` (Claude Code), and `scripts/run-opencode-herdr.sh` (opencode). Use a script preferably!__

### Manual Workflow
1. **Ensure the server is running**: `herdr status`. If not, start with `herdr server`.
2. **Create a workspace** (auto-creates a default tab): `herdr workspace create --label "my-project"`.
3. **Get the default tab and pane**: `herdr tab list --workspace <ws_id>` and `herdr pane list --workspace <ws_id>`.
4. **Start an agent in the default pane**: `herdr agent start "agent-name" --kind pi --pane <pane_id>`.
5. **Send a task (synchronous)**: `herdr agent prompt "agent-name" "your instruction" --wait --timeout 60000`. (Omit `--until` to match `idle|done|blocked` automatically.)
6. **Read output**: `herdr agent read "agent-name" --source recent --lines 100`.

The workflow is complete when `--wait` returns. Verify with `herdr agent list`.

## Helper Scripts

Each script wraps the whole primary workflow (server check → workspace → tab → pane → agent
start → prompt → wait → read output) in one command. Use them for one-shot tasks; drive the CLI
by hand when you need to reuse a workspace or inspect intermediate state.

| Script | Agent kind | Model format |
|--------|-----------|--------------|
| `scripts/run-pi-herdr.sh` | `pi` | `provider/model` (e.g. `evo/ornith-1.0-35b-Q6`) |
| `scripts/run-claude-herdr.sh` | `claude` | alias or full name (`sonnet`, `opus`, `haiku`, `claude-sonnet-4-5`) |
| `scripts/run-opencode-herdr.sh` | `opencode` | `provider/model` (e.g. `anthropic/claude-sonnet-4-5`) |
| `scripts/pipeline-herdr.sh` | multi-stage | per-stage `--<stage>-kind` / `--<stage>-model` |

The three `run-*` scripts share their workflow via `scripts/herdr-common.sh` (sourced, not
executed — edit it to change behavior for all three at once).

**Options shared by all three `run-*` scripts:**

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--model <model>` | `-m` | Model (required) | — |
| `--prompt <text>` | `-p` | Task prompt (required) | — |
| `--timeout <ms>` | `-w` | Wait timeout | `120000` |
| `--name <name>` | `-n` | Agent name | auto from model |
| `--cwd <path>` | `-c` | Workspace working directory | current dir |
| `--label <label>` | `-l` | Workspace label | auto from model |
| `--no-keep` | `-nk` | Close the workspace when done | keep it open |
| `--no-wait` | `-nw` | Fire-and-forget: submit and exit | wait for completion |
| `--help` | `-h` | Full usage and examples | — |

**Agent-specific options:**

| Script | Option | Description |
|--------|--------|-------------|
| pi, claude | `-sp, --system-prompt <text>` | Replace the system prompt (claude also expands `@file`) |
| pi, claude | `-asp, --append-system-prompt <text>` | Append to the system prompt (repeatable) |
| claude | `--agent <name>` / `--agents <json>` | Predefined subagent / inline subagent definitions |
| claude | `--permission-mode <mode>` | `default`, `acceptEdits`, `plan`, `bypassPermissions` |
| claude | `--yolo` | `--dangerously-skip-permissions` (sandboxes only) |
| opencode | `--agent <name>` | Predefined opencode agent (`opencode agent list`) |
| opencode | `--auto` | Auto-approve permissions not explicitly denied (dangerous) |

```bash
# One-shot task, workspace kept open afterwards
scripts/run-pi-herdr.sh -m "evo/ornith-1.0-35b-Q6" -p "Explain src/main.ts"

# Custom cwd and a longer timeout
scripts/run-claude-herdr.sh -m opus -p "Refactor the auth module" -c /path/to/project -w 180000

# Predefined subagent, auto-approve, close the workspace when done
scripts/run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -p "Review the diff" \
    --agent reviewer --auto --no-keep

# Fire-and-forget
scripts/run-pi-herdr.sh -m "qwen3.6-35b" -p "Run the full test suite" --no-wait
```

Run any script with `--help` (or no arguments) for its full option list and examples.

### `pipeline-herdr.sh` (Research → Plan → Implement → Review)

Deterministic multi-stage pipeline: one herdr workspace, one tab + agent per stage, strictly
sequential. Stages hand work forward through files in `<repo>/.agent-work/` (never through
prompt text). Each stage has a mechanical gate; a failed stage is re-run **once** with the gate
requirement and the transcript tail appended to its prompt.

```bash
# Default routing: plan on a strong model, research/implement on a local one
scripts/pipeline-herdr.sh /path/to/repo "Add retry with backoff to the API client"

# Override any stage
scripts/pipeline-herdr.sh /path/to/repo "Refactor config loader" \
    --plan-model opus --implement-model anthropic/claude-sonnet-4-5 --review-kind claude

# Resume after a failure (stages whose gate already passes are skipped)
scripts/pipeline-herdr.sh /path/to/repo --from-stage implement
```

| Stage | Artifact | Gate | Defaults |
|-------|----------|------|----------|
| research | `.agent-work/research.md` | exists, non-empty | `pi` / `dgx/qwen3.6-35b-mtp`, 1h |
| plan | `.agent-work/plan.md` | exists, non-empty | `claude` / `opus`, 1h |
| implement | `.agent-work/results.md` | ends with `RESULTS: all-pass` | `pi` / `dgx/qwen3.6-35b-mtp`, 3h |
| review | `.agent-work/review.md` | ends with `STATUS: clean` or `STATUS: open:<n>` | `pi` / `dgx/qwen3.8-27b`, 1h |

Stage behavior is defined by the static prompt files in `prompts/{research,plan,implement,review}.md`
— edit those to change what a stage does. The review stage re-runs the test commands itself
rather than trusting `results.md`.

**Options:** `--<stage>-kind`, `--<stage>-model`, `--<stage>-timeout <ms>`;
`--from-stage <stage>` (resume), `--fresh` (don't skip passing stages), `--close` (close the
workspace on success). On failure the workspace is kept open — inspect
`.agent-work/<stage>.transcript.md` and `.agent-work/pipeline.log`.

**Exit codes:** `0` clean · `10` research · `11` plan · `12` implement · `13` review produced no
STATUS line · `14` finished with open issues.

## Architecture

> For details, see [ARCHITECTURE.md](./ARCHITECTURE.md).

**Hierarchy:** Session → Workspace → Tab → Pane → Agent.

You can have multiple workspaces in a session, but typically one is enough.

## Core CLI

The commands you need day to day. Full surface: [references/cli-reference.md](./references/cli-reference.md).

```bash
# Server
herdr status                                          # is the server up?
nohup herdr server > /tmp/herdr-server.log 2>&1 &     # start it headless

# Workspace / tab / pane — these print JSON already; do NOT pass --json
herdr workspace create --label "my-project" --cwd /path/to/repo
herdr workspace list
herdr workspace close <ws_id>
herdr tab create --workspace <ws_id> --label "stage-1"
herdr tab list --workspace <ws_id>
herdr pane list --workspace <ws_id>

# Agents
herdr agent start <name> --kind <pi|claude|opencode|codex|...> --pane <pane_id> -- --model <model>
herdr agent prompt <name> "<task>" --wait --timeout 120000
herdr agent read <name> --source recent --lines 200
herdr agent list
herdr agent attach <name>
herdr agent remove <name>

# Notify when something finishes
herdr notification show "Task done" --body "<detail>" --position top-right
```

Pull IDs out of the JSON with `jq`:

```bash
WS=$(herdr workspace create --label demo --cwd "$PWD" | jq -r '.result.workspace.workspace_id')
PANE=$(herdr pane list --workspace "$WS" | jq -r '.result.panes[0].pane_id')
```

`herdr --help` lists every subcommand — it is the best discovery tool.

## Where the rest lives

| File | Contents |
|------|----------|
| [references/cli-reference.md](./references/cli-reference.md) | Full CLI: server, workspaces, tabs, panes, agents, worktrees, notifications, sessions, multi-agent patterns |
| [references/reference.md](./references/reference.md) | Agent integrations, lifecycle reporting API, configuration and updates |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Components, hierarchy, agent statuses |
| `prompts/` | Stage prompts used by `pipeline-herdr.sh` |

## Common Gotchas

1. **Server must be running** before any agent commands work — check with `herdr status`. If not running, start with `herdr server`.
2. **`workspace create`, `tab create`, `pane list`, `agent list`, and `worktree create` do NOT support `--json`** — they output JSON by default. Adding `--json` will fail with "unknown option: --json". Use `--json` only on `status server`, `status client`, `server agent-manifests`, and `api schema`.
3. **`herdr agent start` requires `--kind` and `--pane`** — the old `--workspace --split` syntax is incorrect. The pane must be at an interactive shell prompt.
4. **Use `herdr agent prompt` for AI agents**, not `herdr pane run` — `pane run` is for shell commands; `agent prompt` provides state tracking and synchronous execution.
5. **Agent statuses include `done`** — the full list is: `idle`, `working`, `blocked`, `done`, `unknown`.
6. **`herdr agent send-keys` not `herdr agent send`** — use `send-keys <TARGET> <KEY>...` for key presses.
7. **`herdr session create` does not exist** — sessions are created via `herdr --session <name>` or implicitly.
8. **Agent binary paths vary** — prefer `which <agent>` over hardcoded paths. herdr auto-detects the agent binary for known `--kind` values.
9. **Agent status may show `unknown` briefly after start** — wait a moment before reading output.
10. **`--wait` on `agent prompt` requires a state change** — if the agent is already working, that active turn's completion may match. A stalled agent returns `agent_prompt_stalled` after 5000ms.
11. **Workspace ID parsing** — when capturing workspace_id from JSON output, prefer `herdr workspace get <label>` over fragile grep patterns.
12. **`herdr --help` reveals all available subcommands** — it's the most comprehensive discovery command.
13. **`--until <state>` alone is broken on `agent prompt`** — both `--until done` and `--until idle` time out even when the agent completes. Workarounds: (a) Use `--wait` alone (matches `idle|done|blocked` automatically), (b) Use multiple `--until`: `--wait --until done --until idle`, or (c) Submit without `--wait`, then use `herdr agent wait "name" --until done` separately. Agents transition to `done` (not `idle`) after completing tasks, so `--until idle` will never match a completed agent.
14. **Model formats differ by agent kind** — pi and opencode take `provider/model` (e.g. `anthropic/claude-sonnet-4-5`); claude takes aliases (`sonnet`, `opus`, `haiku`) or full model names. The helper scripts pass `-m` straight through to each agent binary.
15. **claude/opencode must be installed and authenticated** — check `which claude` / `which opencode` (install: `npm install -g @anthropic-ai/claude-code`); authenticate with `claude login` / `opencode auth login`. Without auth the TUI sits on a login prompt and the script blocks until timeout.
16. **`herdr integration install claude` / `herdr integration install opencode`** add lifecycle state hooks for better status tracking (see `herdr integration status`).
