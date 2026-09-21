#!/usr/bin/env bash
# herdr-common.sh — shared workflow for the run-*-herdr.sh scripts.
#
# Sourced, never executed. Before calling the functions the caller must set:
#   AGENT_KIND    herdr --kind value      (pi | claude | opencode)
#   AGENT_PREFIX  agent-name prefix       (pi | cc | oc)
#   LABEL_PREFIX  workspace label prefix  (pi | claude | opencode)
# and must define a usage() function (herdr_parse_common_arg calls it for -h).

# ── Shared defaults ────────────────────────────────────────────────────────
MODEL=""
PROMPT=""
TIMEOUT=120000
AGENT_NAME=""
CWD=""
LABEL=""
KEEP=true
WAIT=true
UNIQUE_SUFFIX="$(printf '%04d' $((RANDOM % 10000)))"  # 4-digit unique suffix for agent names
export HERDR_SHIFT=0

# ── Expand an @file reference to the file's contents ──────────────────────
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

# ── Parse one flag shared by all run scripts ──────────────────────────────
# Call as: herdr_parse_common_arg "$@"
# Sets HERDR_SHIFT to the number of arguments consumed, or 0 if the flag is
# not a common one (the caller then reports an unknown option).
herdr_parse_common_arg() {
    HERDR_SHIFT=2
    case "$1" in
        -m|--model)    MODEL="$2" ;;
        -p|--prompt)   PROMPT="$2" ;;
        -w|--timeout)  TIMEOUT="$2" ;;
        -n|--name)     AGENT_NAME="$2" ;;
        -c|--cwd)      CWD="$2" ;;
        -l|--label)    LABEL="$2" ;;
        -nk|--no-keep) KEEP=false; HERDR_SHIFT=1 ;;
        -nw|--no-wait) WAIT=false; HERDR_SHIFT=1 ;;
        -h|--help)     usage; exit 0 ;;
        *)             HERDR_SHIFT=0 ;;
    esac
}

# ── Validate required flags and derive the defaults taken from the model ──
# Sets MODEL_SHORT and SAFE_MODEL, and fills AGENT_NAME / LABEL / CWD.
herdr_validate_and_defaults() {
    if [[ -z "$MODEL" ]]; then
        echo "ERROR: Model is required. Use -m or --model." >&2
        exit 1
    fi
    if [[ -z "$PROMPT" ]]; then
        echo "ERROR: Prompt is required. Use -p or --prompt." >&2
        exit 1
    fi

    MODEL_SHORT="${MODEL##*/}"  # strip provider prefix
    # Sanitize agent name: lowercase, replace dots with underscores, truncate
    # to 28 chars (leaves room for the prefix = 32 char max).
    SAFE_MODEL="${MODEL_SHORT//./_}"
    SAFE_MODEL="${SAFE_MODEL,,}"
    SAFE_MODEL="${SAFE_MODEL:0:28}"

    if [[ -z "$AGENT_NAME" ]]; then
        AGENT_NAME="${AGENT_PREFIX}-${SAFE_MODEL}-${UNIQUE_SUFFIX}"
    fi
    if [[ -z "$LABEL" ]]; then
        LABEL="${LABEL_PREFIX}-${MODEL_SHORT}-${UNIQUE_SUFFIX}"
    fi
    if [[ -z "$CWD" ]]; then
        CWD="$(pwd)"
    fi
}

# ── Remove a stale agent left behind by an earlier run ────────────────────
herdr_remove_stale_agent() {
    local base="${AGENT_PREFIX}-${SAFE_MODEL}-" stale
    stale=$(herdr agent list 2>/dev/null | jq -r --arg base "$base" '.result.agents[] | select((.name // "") | startswith($base)) | .name' | head -1)
    if [[ -n "$stale" ]]; then
        echo "Removing stale agent: $stale"
        herdr agent remove "$stale" >/dev/null 2>&1 || true
    fi
}

# ── Ensure the herdr server is running ────────────────────────────────────
herdr_ensure_server() {
    if ! herdr status >/dev/null 2>&1; then
        echo "Starting herdr server..."
        nohup herdr server > /tmp/herdr-server.log 2>&1 &
        sleep 2
        if ! herdr status >/dev/null 2>&1; then
            echo "ERROR: herdr server failed to start. Check /tmp/herdr-server.log" >&2
            exit 1
        fi
    fi
}

# ── Create the workspace; sets WS, TAB, PANE ──────────────────────────────
herdr_create_workspace() {
    echo "Creating workspace: $LABEL (cwd: $CWD)"
    WS=$(herdr workspace create --label "$LABEL" --cwd "$CWD" | jq -r '.result.workspace.workspace_id')
    echo "  Workspace ID: $WS"

    # The workspace is created with one default tab and one default pane.
    TAB=$(herdr tab list --workspace "$WS" | jq -r '.result.tabs[0].tab_id')
    echo "  Tab ID: $TAB"

    PANE=$(herdr pane list --workspace "$WS" | jq -r '.result.panes[0].pane_id')
    echo "  Pane ID: $PANE"
}

# ── Pre-accept Claude's one-time workspace trust dialog for <dir> ─────────
# A fresh interactive claude TUI in a never-seen directory blocks on
# "Is this a project you created or one you trust?" and a prompt injected
# into that dialog kills the agent. Trust state lives in ~/.claude.json.
# No-op if the dir is already trusted or the config is missing.
herdr_claude_trust() {
    local dir="$1" cfg="$HOME/.claude.json" trusted tmp
    [[ -f "$cfg" ]] || return 0
    trusted=$(jq -r --arg p "$dir" '.projects[$p].hasTrustDialogAccepted // false' "$cfg" 2>/dev/null)
    if [[ "$trusted" == "true" ]]; then
        return 0
    fi
    tmp="${cfg}.tmp.$$"
    if jq --arg p "$dir" '.projects[$p] = ((.projects[$p] // {}) + {hasTrustDialogAccepted: true})' "$cfg" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$cfg"
        echo "  Pre-accepted Claude workspace trust for $dir"
    else
        rm -f "$tmp"
        echo "WARNING: could not pre-accept Claude workspace trust for $dir (config write failed)" >&2
    fi
    return 0
}

# ── Start the agent; every argument is passed to the agent binary ─────────
herdr_start_agent() {
    local status i
    echo "Starting $AGENT_KIND agent: $AGENT_NAME (model: $MODEL)"

    # The new pane's shell may still be initializing; herdr rejects the
    # start with agent_pane_busy and exits non-zero. Retry until the agent
    # actually shows up in the agent list.
    for i in $(seq 1 15); do
        herdr agent start "$AGENT_NAME" --kind "$AGENT_KIND" --pane "$PANE" -- "$@" || true
        status=$(herdr agent list | jq -r ".result.agents[] | select(.name == \"$AGENT_NAME\") | .agent_status") || true
        if [[ -n "$status" ]]; then
            break
        fi
        echo "  Agent not up yet, retrying start ($i/15)"
        sleep 2
    done

    if [[ -z "$status" ]]; then
        echo "ERROR: Agent '$AGENT_NAME' not found after start." >&2
        echo "Cleaning up workspace..."
        herdr workspace close "$WS" >/dev/null 2>&1
        exit 1
    fi
    echo "  Agent status: $status"

    # Wait for the TUI to reach an idle prompt before submitting.
    # Some agents (e.g. claude) restart their renderer right after start;
    # a prompt sent during that window is silently dropped.
    for _ in $(seq 1 30); do
        status=$(herdr agent list | jq -r ".result.agents[] | select(.name == \"$AGENT_NAME\") | .agent_status")
        [[ "$status" == "idle" ]] && break
        sleep 1
    done
    if [[ "$status" != "idle" ]]; then
        echo "WARNING: Agent did not reach idle (status: ${status}); submitting anyway."
    fi
}

# ── Submit the task; wait and print the output unless --no-wait ───────────
herdr_run_prompt() {
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
        echo ""
        echo "=== Agent Output ==="
        herdr agent read "$AGENT_NAME" --source recent --lines 200
    else
        herdr agent prompt "$AGENT_NAME" "$PROMPT"
    fi
}

# ── Close the workspace, or explain how to reach it ───────────────────────
herdr_finish() {
    echo ""
    if [[ "$KEEP" != true ]]; then
        echo "Closing workspace $WS..."
        herdr workspace close "$WS" >/dev/null 2>&1
    else
        echo "Workspace kept open (ID: $WS). Close with: herdr workspace close $WS"
        echo "Attach with: herdr agent attach $AGENT_NAME"
    fi
}
