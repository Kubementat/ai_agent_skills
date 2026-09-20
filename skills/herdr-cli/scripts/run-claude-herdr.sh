#!/usr/bin/env bash
# run-claude-herdr.sh — Launch a Claude Code agent inside a herdr terminal workspace.
#
# Usage:
#   run-claude-herdr.sh -m <model> -p "<prompt>" [options]
#
# Options:
#   -m, --model <model>              Model to use (required)
#                                    e.g. sonnet, opus, haiku, or full name like claude-sonnet-4-5
#   -p, --prompt <prompt>            Task prompt for the agent (required)
#   -sp, --system-prompt <text>      Replace the system prompt (use @file for file contents)
#   -asp, --append-system-prompt <txt> Append to system prompt (repeatable; use @file for file contents)
#   --agent <name>                   Use a predefined custom agent for the session
#   --agents <json>                  JSON object defining custom agents inline
#   --permission-mode <mode>         Permission mode (default, acceptEdits, plan, bypassPermissions)
#   --yolo                           Bypass all permission checks (--dangerously-skip-permissions)
#   -w, --timeout <ms>               Wait timeout in milliseconds (default: 120000)
#   -n, --name <name>                Agent name (default: auto-generated)
#   -c, --cwd <path>                 Working directory for the workspace (default: current dir)
#   -l, --label <label>              Workspace label (default: based on model name)
#   -nk, --no-keep                   Close workspace after completion (default: kept open)
#   -nw, --no-wait                   Don't wait for agent to finish; exit after prompting
#   -h, --help                       Show this help message
#
# Example:
#   run-claude-herdr.sh -m "sonnet" -p "Explain the code in src/main.ts"
#   run-claude-herdr.sh --model "opus" --prompt "Write a hello world" --timeout 180000
#   run-claude-herdr.sh -m "sonnet" -p "Refactor auth module" -c /path/to/project --no-keep
#   run-claude-herdr.sh -m "sonnet" -p "Code review" --system-prompt "You are a security auditor"
#   run-claude-herdr.sh -m "sonnet" -p "Build a REST API" --agent reviewer --append-system-prompt "Always add tests"
#   run-claude-herdr.sh -m "haiku" -p "Run tests" --yolo

set -euo pipefail

# ── Defaults ───────────────────────────────────────────────────────────────
MODEL=""
PROMPT=""
SYSTEM_PROMPT=""
APPEND_SYSTEM_PROMPTS=()
CLAUDE_AGENT=""
CLAUDE_AGENTS_JSON=""
PERMISSION_MODE=""
YOLO=false
TIMEOUT=120000
AGENT_NAME=""
CWD=""
LABEL=""
KEEP=true
WAIT=true
UNIQUE_SUFFIX="$(printf '%04d' $((RANDOM % 10000)))"  # 4-digit unique suffix for agent names

# ── Usage ──────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: run-claude-herdr.sh -m <model> -p "<prompt>" [options]

Launch a Claude Code agent inside a herdr terminal workspace, submit a task,
wait for completion, and print the output.

Options:
  -m, --model <model>              Model to use (required)
                                    Examples: sonnet, opus, haiku, claude-sonnet-4-5
  -p, --prompt <prompt>            Task prompt for the agent (required)
  -sp, --system-prompt <text>      Replace the system prompt (use @file for file contents)
  -asp, --append-system-prompt <txt> Append to system prompt (repeatable; use @file for file contents)
      --agent <name>               Use a predefined custom agent for the session
      --agents <json>              JSON object defining custom agents inline
      --permission-mode <mode>     Permission mode (default, acceptEdits, plan, bypassPermissions)
      --yolo                       Bypass all permission checks (dangerous; for sandboxes only)
  -w, --timeout <ms>               Wait timeout in milliseconds (default: 120000)
  -n, --name <name>                Agent name (default: auto-generated from model)
  -c, --cwd <path>                 Working directory for the workspace (default: current dir)
  -l, --label <label>              Workspace label (default: based on model name)
  -nk, --no-keep                   Close workspace after completion (default: kept open)
  -nw, --no-wait                   Don't wait for agent to finish; exit after prompting
  -h, --help                       Show this help message

Examples:
  # Simple task with a specific model
  run-claude-herdr.sh -m "sonnet" -p "say hello"

  # Task with custom timeout and working directory
  run-claude-herdr.sh -m "opus" \
      -p "Refactor the auth module" \
      -c /path/to/project \
      -w 180000

  # Close workspace after completion (default is kept open)
  run-claude-herdr.sh -m "haiku" -p "List all .ts files" --no-keep

  # Custom agent name (workspace kept open by default)
  run-claude-herdr.sh -m "sonnet" -n "my-coder" -p "Build a REST API"

  # Use a predefined custom agent and append instructions
  run-claude-herdr.sh -m "sonnet" -p "Review the diff" \
      --agent reviewer \
      --append-system-prompt "Always cite line numbers"

  # Define inline subagents and select one
  run-claude-herdr.sh -m "sonnet" -p "Refactor, then have the reviewer check it" \
      --agents '{"reviewer": {"description": "Reviews code", "prompt": "You are a code reviewer"}}'

  # Bypass permission prompts (sandbox only)
  run-claude-herdr.sh -m "haiku" -p "Run the test suite" --yolo --no-wait
EOF
}

# ── Parse arguments ───────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model)
            MODEL="$2"; shift 2 ;;
        -p|--prompt)
            PROMPT="$2"; shift 2 ;;
        -sp|--system-prompt)
            SYSTEM_PROMPT="$2"; shift 2 ;;
        -asp|--append-system-prompt)
            APPEND_SYSTEM_PROMPTS+=("$2"); shift 2 ;;
        --agent)
            CLAUDE_AGENT="$2"; shift 2 ;;
        --agents)
            CLAUDE_AGENTS_JSON="$2"; shift 2 ;;
        --permission-mode)
            PERMISSION_MODE="$2"; shift 2 ;;
        --yolo)
            YOLO=true; shift ;;
        -w|--timeout)
            TIMEOUT="$2"; shift 2 ;;
        -n|--name)
            AGENT_NAME="$2"; shift 2 ;;
        -c|--cwd)
            CWD="$2"; shift 2 ;;
        -l|--label)
            LABEL="$2"; shift 2 ;;
        -nk|--no-keep)
            KEEP=false; shift ;;
        -nw|--no-wait)
            WAIT=false; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 1 ;;
    esac
done

# ── Validate ──────────────────────────────────────────────────────────────
if [[ -z "$MODEL" ]]; then
    echo "ERROR: Model is required. Use -m or --model." >&2
    exit 1
fi

if [[ -z "$PROMPT" ]]; then
    echo "ERROR: Prompt is required. Use -p or --prompt." >&2
    exit 1
fi

# ── Expand @file references in prompt-like arguments ─────────────────────
expand_file_ref() {
    local arg="$1"
    if [[ "$arg" == @* ]]; then
        local f="${arg#@}"
        if [[ ! -f "$f" ]]; then
            echo "ERROR: File not found for @file reference: $f" >&2
            exit 1
        fi
        cat "$f"
    else
        printf '%s' "$arg"
    fi
}

# ── Defaults from model ───────────────────────────────────────────────────
MODEL_SHORT="${MODEL##*/}"
SAFE_MODEL="${MODEL_SHORT//./_}"
SAFE_MODEL="${SAFE_MODEL,,}"
SAFE_MODEL="${SAFE_MODEL:0:28}"
if [[ -z "$AGENT_NAME" ]]; then
    AGENT_NAME="cc-${SAFE_MODEL}-${UNIQUE_SUFFIX}"
fi
if [[ -z "$LABEL" ]]; then
    LABEL="claude-${MODEL_SHORT}-${UNIQUE_SUFFIX}"
fi
if [[ -z "$CWD" ]]; then
    CWD="$(pwd)"
fi

# ── Remove stale agent with same base name ────────────────────────────────
BASE_AGENT="cc-${SAFE_MODEL}"
STALE=$(herdr agent list 2>/dev/null | jq -r --arg base "$BASE_AGENT-" '.result.agents[] | select((.name // "") | startswith($base)) | .name' | head -1)
if [[ -n "$STALE" ]]; then
    echo "Removing stale agent: $STALE"
    herdr agent remove "$STALE" >/dev/null 2>&1 || true
fi

# ── Ensure herdr server is running ────────────────────────────────────────
if ! herdr status >/dev/null 2>&1; then
    echo "Starting herdr server..."
    nohup herdr server > /tmp/herdr-server.log 2>&1 &
    sleep 2
    if ! herdr status >/dev/null 2>&1; then
        echo "ERROR: herdr server failed to start. Check /tmp/herdr-server.log" >&2
        exit 1
    fi
fi

# ── Create workspace ──────────────────────────────────────────────────────
echo "Creating workspace: $LABEL (cwd: $CWD)"
WS_OUTPUT=$(herdr workspace create --label "$LABEL" --cwd "$CWD")
WS=$(echo "$WS_OUTPUT" | jq -r '.result.workspace.workspace_id')
echo "  Workspace ID: $WS"

# ── Get default tab & pane (workspace creates one automatically) ────────
TAB=$(herdr tab list --workspace "$WS" | jq -r '.result.tabs[0].tab_id')
echo "  Tab ID: $TAB"

PANE=$(herdr pane list --workspace "$WS" | jq -r '.result.panes[0].pane_id')
echo "  Pane ID: $PANE"

# ── Build claude CLI arguments ────────────────────────────────────────────
CLAUDE_ARGS=("--model" "$MODEL")

if [[ -n "$SYSTEM_PROMPT" ]]; then
    CLAUDE_ARGS+=("--system-prompt" "$(expand_file_ref "$SYSTEM_PROMPT")")
fi

for extra in "${APPEND_SYSTEM_PROMPTS[@]+"${APPEND_SYSTEM_PROMPTS[@]}"}"; do
    CLAUDE_ARGS+=("--append-system-prompt" "$(expand_file_ref "$extra")")
done

if [[ -n "$CLAUDE_AGENT" ]]; then
    CLAUDE_ARGS+=("--agent" "$CLAUDE_AGENT")
fi

if [[ -n "$CLAUDE_AGENTS_JSON" ]]; then
    CLAUDE_ARGS+=("--agents" "$CLAUDE_AGENTS_JSON")
fi

if [[ -n "$PERMISSION_MODE" ]]; then
    CLAUDE_ARGS+=("--permission-mode" "$PERMISSION_MODE")
fi

if [[ "$YOLO" == true ]]; then
    CLAUDE_ARGS+=("--dangerously-skip-permissions")
fi

# ── Start claude agent ───────────────────────────────────────────────────
echo "Starting claude agent: $AGENT_NAME (model: $MODEL)"
herdr agent start "$AGENT_NAME" --kind claude --pane "$PANE" -- "${CLAUDE_ARGS[@]}"
# Verify agent started
AGENT_STATUS=$(herdr agent list | jq -r ".result.agents[] | select(.name == \"$AGENT_NAME\") | .agent_status")
if [[ -z "$AGENT_STATUS" ]]; then
    echo "ERROR: Agent '$AGENT_NAME' not found after start." >&2
    echo "Cleaning up workspace..."
    herdr workspace close "$WS" >/dev/null 2>&1
    exit 1
fi
echo "  Agent status: $AGENT_STATUS"

# Wait for the TUI to reach an idle prompt before submitting.
# Some agents (e.g. claude) restart their renderer right after start;
# a prompt sent during that window is silently dropped.
for _ in $(seq 1 30); do
    AGENT_STATUS=$(herdr agent list | jq -r ".result.agents[] | select(.name == \"$AGENT_NAME\") | .agent_status")
    [[ "$AGENT_STATUS" == "idle" ]] && break
    sleep 1
done
if [[ "$AGENT_STATUS" != "idle" ]]; then
    echo "WARNING: Agent did not reach idle (status: ${AGENT_STATUS}); submitting anyway."
fi

# ── Submit task ───────────────────────────────────────────────────────────
echo "Submitting task: $PROMPT"
if [[ "$WAIT" != true ]]; then
    echo "  Mode: fire-and-forget (not waiting for completion)"
else
    echo "  Timeout: ${TIMEOUT}ms"
fi
echo "---"

if [[ "$WAIT" == true ]]; then
    if ! herdr agent prompt "$AGENT_NAME" "$PROMPT" --wait --timeout "$TIMEOUT"; then
        echo "WARNING: Prompt may not have been delivered (no state change); retrying once..." >&2
        sleep 2
        herdr agent prompt "$AGENT_NAME" "$PROMPT" --wait --timeout "$TIMEOUT"
    fi

    # ── Read output ───────────────────────────────────────────────────────
    echo ""
    echo "=== Agent Output ==="
    herdr agent read "$AGENT_NAME" --source recent --lines 200
else
    herdr agent prompt "$AGENT_NAME" "$PROMPT"
fi

# ── Cleanup ───────────────────────────────────────────────────────────────
if [[ "$KEEP" != true ]]; then
    echo ""
    echo "Closing workspace $WS..."
    herdr workspace close "$WS" >/dev/null 2>&1
else
    echo ""
    echo "Workspace kept open (ID: $WS). Close with: herdr workspace close $WS"
    echo "Attach with: herdr agent attach $AGENT_NAME"
fi
