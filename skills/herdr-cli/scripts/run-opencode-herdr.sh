#!/usr/bin/env bash
# run-opencode-herdr.sh — Launch an opencode agent inside a herdr terminal workspace.
#
# Usage:
#   run-opencode-herdr.sh -m <provider/model> -p "<prompt>" [options]
#
# Options:
#   -m, --model <provider/model>     Model to use (required), e.g. anthropic/claude-sonnet-4-5
#   -p, --prompt <prompt>            Task prompt for the agent (required)
#   --agent <name>                   Predefined opencode agent to use (subagent orchestration)
#   --auto                           Auto-approve permissions not explicitly denied (dangerous!)
#   -w, --timeout <ms>               Wait timeout in milliseconds (default: 120000)
#   -n, --name <name>                Agent name (default: auto-generated)
#   -c, --cwd <path>                 Working directory for the workspace (default: current dir)
#   -l, --label <label>              Workspace label (default: based on model name)
#   -nk, --no-keep                   Close workspace after completion (default: kept open)
#   -nw, --no-wait                   Don't wait for agent to finish; exit after prompting
#   -h, --help                       Show this help message
#
# Example:
#   run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -p "Explain the code in src/main.ts"
#   run-opencode-herdr.sh --model "google/gemini-2.5-pro" --prompt "Write a hello world" --timeout 180000
#   run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -p "Refactor auth module" -c /path/to/project --no-keep
#   run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -p "Code review" --agent reviewer --auto

set -euo pipefail

# ── Defaults ───────────────────────────────────────────────────────────────
MODEL=""
PROMPT=""
OPENCODE_AGENT=""
AUTO=false
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
Usage: run-opencode-herdr.sh -m <provider/model> -p "<prompt>" [options]

Launch an opencode agent inside a herdr terminal workspace, submit a task,
wait for completion, and print the output.

Options:
  -m, --model <provider/model>     Model to use (required)
                                    Examples: anthropic/claude-sonnet-4-5, google/gemini-2.5-pro,
                                              openai/gpt-4o
  -p, --prompt <prompt>            Task prompt for the agent (required)
      --agent <name>               Predefined opencode agent to use (see `opencode agent list`)
      --auto                       Auto-approve permissions not explicitly denied (dangerous!)
  -w, --timeout <ms>               Wait timeout in milliseconds (default: 120000)
  -n, --name <name>                Agent name (default: auto-generated from model)
  -c, --cwd <path>                 Working directory for the workspace (default: current dir)
  -l, --label <label>              Workspace label (default: based on model name)
  -nk, --no-keep                   Close workspace after completion (default: kept open)
  -nw, --no-wait                   Don't wait for agent to finish; exit after prompting
  -h, --help                       Show this help message

Examples:
  # Simple task with a specific model
  run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -p "say hello"

  # Task with custom timeout and working directory
  run-opencode-herdr.sh -m "google/gemini-2.5-pro" \
      -p "Refactor the auth module" \
      -c /path/to/project \
      -w 180000

  # Close workspace after completion (default is kept open)
  run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -p "List all .ts files" --no-keep

  # Custom agent name (workspace kept open by default)
  run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -n "my-coder" -p "Build a REST API"

  # Use a predefined opencode agent (subagent) with auto-approve
  run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -p "Review the diff" --agent reviewer --auto

  # Fire-and-forget: start agent, submit task, exit immediately
  run-opencode-herdr.sh -m "openai/gpt-4o" -p "Run the full test suite" --no-wait
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
        --agent)
            OPENCODE_AGENT="$2"; shift 2 ;;
        --auto)
            AUTO=true; shift ;;
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

# ── Defaults from model ───────────────────────────────────────────────────
MODEL_SHORT="${MODEL##*/}"
SAFE_MODEL="${MODEL_SHORT//./_}"
SAFE_MODEL="${SAFE_MODEL,,}"
SAFE_MODEL="${SAFE_MODEL:0:28}"
if [[ -z "$AGENT_NAME" ]]; then
    AGENT_NAME="oc-${SAFE_MODEL}-${UNIQUE_SUFFIX}"
fi
if [[ -z "$LABEL" ]]; then
    LABEL="opencode-${MODEL_SHORT}-${UNIQUE_SUFFIX}"
fi
if [[ -z "$CWD" ]]; then
    CWD="$(pwd)"
fi

# ── Remove stale agent with same base name ────────────────────────────────
BASE_AGENT="oc-${SAFE_MODEL}"
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

# ── Build opencode CLI arguments ──────────────────────────────────────────
OC_ARGS=("--model" "$MODEL")

if [[ -n "$OPENCODE_AGENT" ]]; then
    OC_ARGS+=("--agent" "$OPENCODE_AGENT")
fi

if [[ "$AUTO" == true ]]; then
    OC_ARGS+=("--auto")
fi

# ── Start opencode agent ─────────────────────────────────────────────────
echo "Starting opencode agent: $AGENT_NAME (model: $MODEL)"
herdr agent start "$AGENT_NAME" --kind opencode --pane "$PANE" -- "${OC_ARGS[@]}"
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
