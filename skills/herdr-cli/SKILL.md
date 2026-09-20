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

Convenience scripts ship with this skill. Each wraps the full primary workflow (server check → workspace → tab → pane → agent start → prompt → wait → read output) into a single command. Use them when you want to fire off a quick task without chaining 6+ CLI calls.

| Script | Agent kind | Model format |
|--------|-----------|--------------|
| `scripts/run-pi-herdr.sh` | `pi` | `provider/model` (e.g. `evo/ornith-1.0-35b-Q6`, `anthropic/claude-sonnet-4`) |
| `scripts/pipeline-herdr.sh` | multi-stage | per-stage `--<stage>-kind` / `--<stage>-model` (see Pipeline below) |
| `scripts/run-claude-herdr.sh` | `claude` | Alias or full name (e.g. `sonnet`, `opus`, `haiku`, `claude-sonnet-4-5`) |
| `scripts/run-opencode-herdr.sh` | `opencode` | `provider/model` (e.g. `anthropic/claude-sonnet-4-5`, `google/gemini-2.5-pro`) |

All three share the same workflow options: `-p/--prompt`, `-w/--timeout` (default 120000), `-n/--name`, `-c/--cwd`, `-l/--label`, `-nk/--no-keep`, `-nw/--no-wait`, `-h/--help`.

### `run-claude-herdr.sh` (Claude Code)

Agent-specific options:

| Option | Description |
|--------|-------------|
| `-m, --model <model>` | Model (required), e.g. `sonnet`, `opus`, `haiku` |
| `-sp, --system-prompt <text>` | Replace the system prompt (`@file` supported) |
| `-asp, --append-system-prompt <txt>` | Append to system prompt (repeatable, `@file` supported) |
| `--agent <name>` | Use a predefined custom agent |
| `--agents <json>` | Define custom agents inline (JSON) |
| `--permission-mode <mode>` | `default`, `acceptEdits`, `plan`, `bypassPermissions` |
| `--yolo` | Bypass all permission checks (`--dangerously-skip-permissions`; sandboxes only) |

```bash
# Claude Code task with a predefined subagent
scripts/run-claude-herdr.sh -m "sonnet" -p "Review the diff" --agent reviewer

# Inline subagents + permission mode, custom cwd
scripts/run-claude-herdr.sh -m "opus" -p "Refactor auth, then review it" \
    --agents '{"reviewer": {"description": "Reviews code", "prompt": "You are a code reviewer"}}' \
    --permission-mode acceptEdits -c /path/to/project
```

### `run-opencode-herdr.sh` (opencode)

Agent-specific options:

| Option | Description |
|--------|-------------|
| `-m, --model <provider/model>` | Model (required), e.g. `anthropic/claude-sonnet-4-5` |
| `--agent <name>` | Predefined opencode agent (see `opencode agent list`) |
| `--auto` | Auto-approve permissions not explicitly denied (dangerous!) |

```bash
# opencode task with a predefined subagent
scripts/run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -p "Review the diff" --agent reviewer

# Model + auto-approve, close workspace when done
scripts/run-opencode-herdr.sh -m "google/gemini-2.5-pro" -p "Run the tests" --auto --no-keep
```

### `run-pi-herdr.sh`

#### Usage

```bash
scripts/run-pi-herdr.sh -m <model> -p "<prompt>" [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--model <model>` | `-m` | Model to use (required) | — |
| `--prompt <prompt>` | `-p` | Task prompt (required) | — |
| `--system-prompt <text>` | `-sp` | Replace pi's system prompt entirely | pi's default |
| `--append-system-prompt <txt>` | `-asp` | Append to system prompt (repeatable, `@file` supported) | — |
| `--timeout <ms>` | `-w` | Wait timeout in milliseconds | `120000` |
| `--name <name>` | `-n` | Agent name | Auto-generated from model |
| `--cwd <path>` | `-c` | Working directory for workspace | Current directory |
| `--label <label>` | `-l` | Workspace label | Based on model name |
| `--no-keep` | `-nk` | Close workspace after completion | Workspace kept open |
| `--no-wait` | `-nw` | Fire-and-forget: submit prompt and exit immediately (do not wait for agent completion) | Waits for completion |
| `--help` | `-h` | Show help | — |

### Examples

```bash
# Quick task with a specific model
scripts/run-pi-herdr.sh -m "evo/ornith-1.0-35b-Q6" -p "Explain the code in src/main.ts"

# Task with custom timeout and working directory
scripts/run-pi-herdr.sh -m "anthropic/claude-sonnet-4" \\
    -p "Refactor the auth module" \\
    -c /path/to/project \\
    -w 180000

# Close workspace after completion
scripts/run-pi-herdr.sh -m "qwen3.6-35b" -p "List all .ts files" --no-keep

# Custom agent name (workspace kept open)
scripts/run-pi-herdr.sh -m "evo/ornith-1.0-35b-Q6" -n "my-coder" -p "Build a REST API"

# Replace the system prompt entirely
scripts/run-pi-herdr.sh -sp "You are a senior security auditor focused on finding vulnerabilities." \
    -m "claude-sonnet-4" -p "Code review"

# Append extra instructions (repeatable, supports @file syntax)
scripts/run-pi-herdr.sh -m "gpt-4o" -p "Build a REST API" \
    -asp "Always write tests alongside code" \
    -asp "@coding-standards.md"

# Fire-and-forget: start agent, submit task, exit immediately
scripts/run-pi-herdr.sh -m "qwen3.6-35b" -p "Run the full test suite" --no-wait
```

### `pipeline-herdr.sh` (Research → Plan → Implement → Review)

Deterministic multi-stage pipeline: one herdr workspace, one tab + agent per stage, strictly sequential. Stages hand work forward via files in `<repo>/.agent-work/` (never via prompt text). Each stage has a mechanical gate; a failed stage is re-run **once** with the failure gate + transcript tail appended to the prompt.

```bash
# Default model routing: plan on strong model, research/implement on local
scripts/pipeline-herdr.sh /path/to/repo "Add retry with backoff to the API client"

# Override any stage's agent kind + model
scripts/pipeline-herdr.sh /path/to/repo "Refactor config loader" \
    --research-model opus \
    --implement-model anthropic/claude-sonnet-4-5 \
    --review-kind claude --review-model opus

# Resume after a failure (skips earlier stages whose gates already pass)
scripts/pipeline-herdr.sh /path/to/repo --from-stage implement
```

**Defaults:** research `pi`/`dgx/qwen3.6-35b-mtp`, plan `claude`/`opus`, implement `pi`/`dgx/qwen3.6-35b-mtp`, review `pi`/`dgx/qwen3.8-27b`. Timeouts: 1h per stage, 3h for implement.

**Stage prompts** are static files in `prompts/{research,plan,implement,review}.md` next to the skill — edit them there to change stage behavior. Each prompt defines the artifact contract:

| Stage | Artifact | Gate |
|-------|----------|------|
| research | `.agent-work/research.md` | exists, non-empty |
| plan | `.agent-work/plan.md` | exists, non-empty |
| implement | `.agent-work/results.md` | ends with `RESULTS: all-pass` |
| review | `.agent-work/review.md` | ends with `STATUS: clean` or `STATUS: open:<n>` |

The review stage re-runs all test commands itself (it does not trust `results.md`), fixes what it can, and reports open issues.

**Options:** `--<stage>-kind`, `--<stage>-model`, `--<stage>-timeout <ms>` per stage; `--from-stage <research|plan|implement|review>` (resume), `--fresh` (don't skip already-passing stages), `--close` (close workspace on success). Workspace is kept open on failure — inspect `<stage>.transcript.md` and `pipeline.log` in `.agent-work/`.

**Exit codes:** `0` clean · `10` research failed · `11` plan failed · `12` implement failed · `13` review failed (no STATUS line) · `14` finished with open issues (`STATUS: open:<n>`).

### When to Use the Script vs Manual CLI

| Use the script when | Use manual CLI when |
|---------------------|---------------------|
| Single quick task | Multi-step chained workflow |
| One-shot agent run | You need fine-grained control over panes/tabs |
| Different models per task | You want to reuse an existing workspace |
| Scripted/automated pipelines | You need to inspect intermediate state |

## Architecture

> For details, see [ARCHITECTURE.md](./ARCHITECTURE.md).

**Hierarchy:** Session → Workspace → Tab → Pane → Agent.

You can have multiple workspaces in a session, but typically one is enough.

## Server Management

```bash
# Start the daemon in background (headless server)
nohup herdr server > /tmp/herdr-server.log 2>&1 &
sleep 2

# Verify it started
herdr status

# Detailed server status (JSON)
herdr status server --json

# Client status (JSON)
herdr status client --json

# Stop the server
herdr server stop

# Reload config in running server
herdr server reload-config
```

## Creating a Workspace

```bash
# Create a workspace with a label
herdr workspace create --label "my-project"

# Create with a working directory
herdr workspace create --label "my-project" --cwd /path/to/project

# Create with environment variables
herdr workspace create --label "my-project" --env MY_VAR=value

# Create and focus
herdr workspace create --label "my-project" --focus

# List workspaces
herdr workspace list

# Get workspace details
herdr workspace get <workspace_id>

# Focus a workspace
herdr workspace focus <workspace_id>

# Rename a workspace
herdr workspace rename <workspace_id> <new-label>

# Close a workspace
herdr workspace close <workspace_id>

# Report workspace metadata (display-only tokens)
herdr workspace report-metadata --source <ID> <workspace_id> --token NAME=value
```

## Tab Management

```bash
# Create a tab in a workspace
herdr tab create --workspace <workspace_id> --label "agent-name" --cwd /path

# Create with environment variables
herdr tab create --workspace <workspace_id> --env KEY=VALUE --label "tab-name"

# Create and focus
herdr tab create --workspace <workspace_id> --label "tab-name" --focus

# List tabs (optionally scoped to a workspace)
herdr tab list --workspace <workspace_id>

# Get tab details
herdr tab get <tab_id>

# Focus a tab
herdr tab focus <tab_id>

# Rename a tab
herdr tab rename <tab_id> <new-label>

# Close a tab
herdr tab close <tab_id>
```

## Pane Management

```bash
# List panes (optionally scoped to a workspace)
herdr pane list --workspace <workspace_id>

# Show the current pane
herdr pane current

# Show pane details
herdr pane get <pane_id>

# Run a shell command in a pane (sends text + Enter)
herdr pane run <pane_id> "echo hello"

# Split a pane
herdr pane split <pane_id> --direction right --ratio 0.5 --cwd /path
herdr pane split --current --direction down
herdr pane split <pane_id> --direction right --env KEY=value --focus

# Resize a pane
herdr pane resize --direction right --amount 0.3 --pane <pane_id>

# Zoom/unzoom a pane
herdr pane zoom <pane_id> --toggle
herdr pane zoom --current --on
herdr pane zoom --current --off

# Focus a pane by direction
herdr pane focus --direction left
herdr pane focus --direction right
herdr pane focus --direction up
herdr pane focus --direction down

# Send raw text to a pane (no Enter)
herdr pane send-text <pane_id> "text"

# Send key presses to a pane
herdr pane send-keys <pane_id> Return
herdr pane send-keys <pane_id> Ctrl+c
herdr pane send-keys <pane_id> esc

# Read pane output
herdr pane read <pane_id> --source visible --lines 50
herdr pane read <pane_id> --source recent --lines 50 --format ansi
herdr pane read <pane_id> --source recent --lines 50 --ansi
herdr pane read <pane_id> --source recent --lines 50 --raw
herdr pane read <pane_id> --source detection

# Wait for matching output in a pane (--match and --regex are mutually exclusive, one is required)
herdr pane wait-output <pane_id> --match "Ready" --timeout 30000
herdr pane wait-output <pane_id> --regex "Done: .*" --timeout 60000
herdr pane wait-output <pane_id> --match "complete" --source recent --lines 100

# Close a pane
herdr pane close <pane_id>

# Rename a pane
herdr pane rename <pane_id> <label>

# Swap two panes
herdr pane swap --source-pane <pane_a> --target-pane <pane_b>
herdr pane swap --direction right --current

# Move a pane to another tab, workspace, or split
herdr pane move <pane_id> --tab <tab_id>
herdr pane move <pane_id> --workspace <workspace_id>
herdr pane move <pane_id> --new-tab --label "new-tab"
herdr pane move <pane_id> --new-workspace --label "new-ws"
herdr pane move <pane_id> --split right --target-pane <pane_id> --ratio 0.5

# Layout introspection
herdr pane layout --pane <pane_id>
herdr pane edges --pane <pane_id>
herdr pane neighbor --direction right --pane <pane_id>
herdr pane process-info --pane <pane_id>
```

## Agent Management

### Starting Agents

```bash
# Start a supported agent in an existing pane (pane must be at shell prompt)
herdr agent start "agent-name" --kind pi --pane <pane_id>

# Start with custom timeout (default: 30000ms, max: 300000ms)
herdr agent start "agent-name" --kind claude --pane <pane_id> --timeout 60000

# Start with agent-specific arguments
herdr agent start "agent-name" --kind codex --pane <pane_id> -- --some-flag
```

**Supported agent kinds:**
`pi`, `claude`, `codex`, `gemini`, `cursor`, `devin`, `agy`, `cline`, `omp`, `mastracode`, `opencode`, `copilot`, `kimi`, `kiro`, `droid`, `amp`, `grok`, `hermes`, `kilo`, `qodercli`, `maki`

### Submitting Tasks to Agents

```bash
# Submit a prompt (PRIMARY method for AI agents)
herdr agent prompt "agent-name" "Your instruction here"

# Synchronous: wait for agent to finish (returns when agent reaches idle, done, or blocked)
herdr agent prompt "agent-name" "Your instruction here" --wait

# Wait for specific status (NOTE: --until done/idle alone is BROKEN on agent prompt — see Gotcha #13)
# WORKAROUND: use --wait alone (matches idle|done|blocked), or use --until with multiple values:
herdr agent prompt "agent-name" "Your instruction here" --wait --until done --until idle

# With timeout (milliseconds)
herdr agent prompt "agent-name" "Your instruction here" --wait --timeout 60000
```

### Waiting for Agent Status

```bash
# Wait for agent to reach idle, done, or blocked (default)
herdr agent wait "agent-name"

# Wait for specific status (agents transition to 'done', not 'idle', after completing tasks)
herdr agent wait "agent-name" --until done
herdr agent wait "agent-name" --until working
herdr agent wait "agent-name" --until blocked
herdr agent wait "agent-name" --until unknown

# Wait for multiple possible statuses
herdr agent wait "agent-name" --until done --until idle

# With timeout
herdr agent wait "agent-name" --until idle --timeout 60000

# Without --until, matches idle, done, or blocked; without --timeout, waits indefinitely
```

### Reading Agent Output

```bash
# Read recent output from an agent
herdr agent read "agent-name" --source recent --lines 50

# Read visible pane content
herdr agent read "agent-name" --source visible --lines 50

# Read unwrapped output (no line wrapping artifacts)
herdr agent read "agent-name" --source recent-unwrapped --lines 50

# Read with ANSI codes
herdr agent read "agent-name" --source recent --format ansi
herdr agent read "agent-name" --source recent --ansi

# Read raw output (no processing)
herdr agent read "agent-name" --source recent --raw

# Read detection source (agent detection info)
herdr agent read "agent-name" --source detection
```

### Sending Keys to Agents

```bash
# Send key presses (use esc, not escape)
herdr agent send-keys "agent-name" Return
herdr agent send-keys "agent-name" Ctrl+c
herdr agent send-keys "agent-name" esc
```

### Other Agent Commands

```bash
# List all agents
herdr agent list

# Get details on a specific agent
herdr agent get "agent-name"

# Rename an agent
herdr agent rename "agent-name" "new-name"

# Clear agent name
herdr agent rename "agent-name" --clear

# Focus an agent's pane
herdr agent focus "agent-name"

# Attach to an agent's terminal (interactive takeover)
herdr agent attach "agent-name" [--takeover]

# Explain agent detection state
herdr agent explain "agent-name" --format json
herdr agent explain "agent-name" --json          # alias for --format json
herdr agent explain "agent-name" --verbose       # detailed text output
herdr agent explain "agent-name" --verbose --json # JSON with extra fields
herdr agent explain --file PATH --agent "agent-name"
```

## AI Agent Integration

> See [references/reference.md](./references/reference.md#ai-agent-integration) for installing integrations and agent manifest management.

## Synchronous Task Execution

The primary pattern for AI agent workflows is synchronous task submission with `herdr agent prompt --wait`:

```bash
# Basic synchronous task (waits for idle, done, or blocked)
herdr agent prompt "coder" "Implement the login feature" --wait

# Wait with timeout (recommended: omit --until to match any terminal state)
herdr agent prompt "coder" "Refactor the auth module" --wait --timeout 120000

# Full synchronous workflow: submit, wait, read results
herdr agent prompt "coder" "Implement the login feature" --wait --timeout 120000
herdr agent read "coder" --source recent --lines 200

# Alternative: submit then wait separately (more reliable than --until on agent prompt)
herdr agent prompt "coder" "Run the test suite"
herdr agent wait "coder" --until done --timeout 300000
herdr agent read "coder" --source recent --lines 200

# Chain multiple tasks
herdr agent prompt "coder" "Create the project structure" --wait --timeout 60000
herdr agent prompt "coder" "Add the main module" --wait --timeout 60000
herdr agent prompt "coder" "Write unit tests" --wait --timeout 90000
herdr agent read "coder" --source recent --lines 300
```

### Polling for Output Patterns

Use `herdr pane wait-output` to wait for specific output patterns:

```bash
# Wait for literal text to appear
herdr pane wait-output <pane_id> --match "All tests passed" --timeout 60000

# Wait for regex pattern
herdr pane wait-output <pane_id> --regex "Build\s+success" --timeout 120000

# Search existing output first, then poll
herdr pane wait-output <pane_id> --match "Ready" --source recent --lines 200

# With ANSI codes preserved
herdr pane wait-output <pane_id> --match "DONE" --raw --timeout 30000
```

## Custom Agent Integration

> See [references/reference.md](./references/reference.md#custom-agent-integration) for lifecycle reporting, session identity, metadata, and the full integration pattern.

## Git Worktree for Isolated Agent Environments

herdr provides Git worktree helpers to create isolated workspaces per branch:

```bash
# List worktree workspaces
herdr worktree list

# Create and open a new worktree for a branch
herdr worktree create --branch feature-x --label "feature-x" --focus

# Create with specific workspace and path
herdr worktree create --workspace <ws_id> --branch feature-x --path /tmp/feature-x --label "feature-x"

# Create from a base ref
herdr worktree create --branch feature-x --base main --cwd /path/to/repo

# Open an existing worktree
herdr worktree open --branch feature-x --path /tmp/feature-x --label "feature-x"
herdr worktree open --workspace <ws_id> --path /tmp/feature-x --focus

# Remove a worktree checkout
herdr worktree remove --workspace <ws_id>
herdr worktree remove --force
```

### Worktree Workflow for Parallel Agent Work

```bash
# Create worktrees for multiple feature branches
herdr worktree create --branch feature-auth --label "auth" --focus
herdr worktree create --branch feature-api --label "api"
herdr worktree create --branch feature-ui --label "ui"

# Each worktree gets its own workspace with isolated git state
# Start agents in each workspace for parallel development
```

## Notification System

herdr supports desktop notifications for agent completion alerts:

```bash
# Show a notification
herdr notification show "Task Complete" --body "Agent finished the task"

# With position and sound
herdr notification show "Build Done" --body "All tests passed" --position top-right --sound done

# Notification positions
herdr notification show "Alert" --position top-left
herdr notification show "Alert" --position top-right
herdr notification show "Alert" --position bottom-left
herdr notification show "Alert" --position bottom-right

# Sound options
herdr notification show "Done" --sound done
herdr notification show "Request" --sound request
herdr notification show "Silent" --sound none
```

### Notification Pattern for Task Completion

```bash
# Submit task and notify on completion
herdr agent prompt "coder" "Implement feature X" --wait --timeout 300000
herdr notification show "Task Complete" --body "Feature X implementation done" --position top-right --sound done
```

## Session Management

```bash
# List sessions
herdr session list

# Use or create a named session (via --session flag on main command)
herdr --session "my-session"

# Attach to a named session
herdr session attach <name>

# Stop a session
herdr session stop <name>
herdr session stop default    # Stop the default session

# Delete a stopped session
herdr session delete <name>
```

## Configuration and Updates

> See [references/reference.md](./references/reference.md#configuration-and-updates) for config, updates, shell completions, and API schema.

## Useful Patterns

### Launch 2 Agents for Parallel Work

```bash
# Create workspace (auto-creates default tab with default pane)
WS=$(herdr workspace create --label "parallel" | grep -o '"workspace_id":"[^"]*"' | cut -d'"' -f4)

# Use the default tab for the first agent
T1=$(herdr tab list --workspace "$WS" | jq -r '.result.tabs[0].tab_id')
P1=$(herdr pane list --workspace "$WS" | jq -r '.result.panes[0].pane_id')
herdr agent start "researcher" --kind pi --pane "$P1"
sleep 2

# Create a second tab for the second agent
T2=$(herdr tab create --workspace "$WS" --label "coder" | jq -r '.result.tab.tab_id')
P2=$(herdr pane list --workspace "$WS" | jq -r '.result.panes[-1].pane_id')
herdr agent start "coder" --kind pi --pane "$P2"
sleep 2

# Assign tasks synchronously
herdr agent prompt "researcher" "Research the requirements for feature X" --wait --timeout 120000
herdr agent prompt "coder" "Implement the feature based on requirements" --wait --timeout 180000
```

### Check All Agent Statuses

```bash
herdr agent list | jq '.result.agents[] | {name: .name, status: .agent_status}'
```

### Get Live Runtime Snapshot

```bash
herdr api snapshot
```

### Remote Session Attachment

```bash
# Attach to a remote herdr server via SSH
herdr --remote user@host

# Attach to a remote session
herdr --remote user@host --session "my-session"

# With handoff for live transition
herdr --remote user@host --handoff
```

### Monolithic Mode (No Server)

```bash
# Run without server/client split (escape hatch)
herdr --no-session
```

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
