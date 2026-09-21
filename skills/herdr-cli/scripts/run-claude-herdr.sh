#!/usr/bin/env bash
# run-claude-herdr.sh — Launch a Claude Code agent inside a herdr terminal workspace.
# Run with --help for usage and examples.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-common.sh"
# shellcheck disable=SC2034
AGENT_KIND="claude"
# shellcheck disable=SC2034
AGENT_PREFIX="cc"
# shellcheck disable=SC2034
LABEL_PREFIX="claude"
SYSTEM_PROMPT=""
APPEND_SYSTEM_PROMPTS=()
CLAUDE_AGENT=""
CLAUDE_AGENTS_JSON=""
PERMISSION_MODE=""
YOLO=false
usage() {
    cat <<'USAGE'
Usage: run-claude-herdr.sh -m <model> -p "<prompt>" [options]
Launch a Claude Code agent inside a herdr terminal workspace, submit a task,
wait for completion, and print the output.
Options:
  -m, --model <model>              Model (required), e.g. sonnet, opus, haiku
  -p, --prompt <prompt>            Task prompt (required)
  -sp, --system-prompt <text>      Replace system prompt (@file supported)
  -asp, --append-system-prompt <txt> Append to system prompt (repeatable, @file)
  -w, --timeout <ms>               Wait timeout (default: 120000)
  -n, --name <name>                Agent name (default: auto-generated)
  -c, --cwd <path>                 Working directory (default: current dir)
  -l, --label <label>              Workspace label (default: based on model)
  -nk, --no-keep                   Close workspace after completion
  -nw, --no-wait                   Fire-and-forget: exit after prompting
  -h, --help                       Show this help message
      --agent <name>               Predefined custom agent
      --agents <json>              Inline subagent definitions (JSON)
      --permission-mode <mode>     default, acceptEdits, plan, bypassPermissions
      --yolo                       Bypass all permissions (sandbox only)
Examples:
  run-claude-herdr.sh -m "sonnet" -p "Explain src/main.ts"
  run-claude-herdr.sh -m "opus" -p "Refactor auth" --yolo --no-keep
USAGE
}
[[ $# -eq 0 ]] && usage && exit 0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -sp|--system-prompt)  SYSTEM_PROMPT="$2"; shift 2 ;;
        -asp|--append-system-prompt) APPEND_SYSTEM_PROMPTS+=("$2"); shift 2 ;;
        --agent)              CLAUDE_AGENT="$2"; shift 2 ;;
        --agents)             CLAUDE_AGENTS_JSON="$2"; shift 2 ;;
        --permission-mode)    PERMISSION_MODE="$2"; shift 2 ;;
        --yolo)               YOLO=true; shift ;;
        *)
            herdr_parse_common_arg "$@"
            if [[ "$HERDR_SHIFT" -eq 0 ]]; then
                echo "ERROR: Unknown option: $1" >&2
                echo "Use --help for usage information." >&2
                exit 1
            fi
            shift "$HERDR_SHIFT" ;;
    esac
done
herdr_validate_and_defaults
herdr_remove_stale_agent
herdr_ensure_server
herdr_create_workspace
CLAUDE_ARGS=("--model" "$MODEL")
[[ -n "$SYSTEM_PROMPT" ]] && CLAUDE_ARGS+=("--system-prompt" "$(expand_file_ref "$SYSTEM_PROMPT")")
for extra in "${APPEND_SYSTEM_PROMPTS[@]+"${APPEND_SYSTEM_PROMPTS[@]}"}"; do
    CLAUDE_ARGS+=("--append-system-prompt" "$(expand_file_ref "$extra")")
done
[[ -n "$CLAUDE_AGENT" ]] && CLAUDE_ARGS+=("--agent" "$CLAUDE_AGENT")
[[ -n "$CLAUDE_AGENTS_JSON" ]] && CLAUDE_ARGS+=("--agents" "$CLAUDE_AGENTS_JSON")
[[ -n "$PERMISSION_MODE" ]] && CLAUDE_ARGS+=("--permission-mode" "$PERMISSION_MODE")
[[ "$YOLO" == true ]] && CLAUDE_ARGS+=("--dangerously-skip-permissions")
herdr_claude_trust "$CWD"
herdr_start_agent "${CLAUDE_ARGS[@]}"
herdr_run_prompt
herdr_finish
