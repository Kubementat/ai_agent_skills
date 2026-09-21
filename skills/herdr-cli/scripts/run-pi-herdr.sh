#!/usr/bin/env bash
# run-pi-herdr.sh — Launch a pi agent inside a herdr terminal workspace.
# Run with --help for usage and examples.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-common.sh"
# shellcheck disable=SC2034
AGENT_KIND="pi"
# shellcheck disable=SC2034
AGENT_PREFIX="pi"
# shellcheck disable=SC2034
LABEL_PREFIX="pi"
SYSTEM_PROMPT=""
APPEND_SYSTEM_PROMPTS=()
usage() {
    cat <<'USAGE'
Usage: run-pi-herdr.sh -m <model> -p "<prompt>" [options]
Launch a pi coding agent inside a herdr terminal workspace, submit a task,
wait for completion, and print the output.
Options:
  -m, --model <model>              Model (required), e.g. evo/ornith-1.0-35b-Q6
  -p, --prompt <prompt>            Task prompt (required)
  -sp, --system-prompt <text>      Replace pi's system prompt
  -asp, --append-system-prompt <txt> Append to system prompt (repeatable, @file)
  -w, --timeout <ms>               Wait timeout (default: 120000)
  -n, --name <name>                Agent name (default: auto-generated)
  -c, --cwd <path>                 Working directory (default: current dir)
  -l, --label <label>              Workspace label (default: based on model)
  -nk, --no-keep                   Close workspace after completion
  -nw, --no-wait                   Fire-and-forget: exit after prompting
  -h, --help                       Show this help message
Examples:
  run-pi-herdr.sh -m "evo/ornith-1.0-35b-Q6" -p "Explain src/main.ts"
  run-pi-herdr.sh -m "qwen3.6-35b" -p "Run tests" --no-wait
USAGE
}
[[ $# -eq 0 ]] && usage && exit 0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -sp|--system-prompt)  SYSTEM_PROMPT="$2"; shift 2 ;;
        -asp|--append-system-prompt) APPEND_SYSTEM_PROMPTS+=("$2"); shift 2 ;;
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
PI_ARGS=("--model" "$MODEL")
[[ -n "$SYSTEM_PROMPT" ]] && PI_ARGS+=("--system-prompt" "$SYSTEM_PROMPT")
for extra in "${APPEND_SYSTEM_PROMPTS[@]+"${APPEND_SYSTEM_PROMPTS[@]}"}"; do
    PI_ARGS+=("--append-system-prompt" "$extra")
done
herdr_start_agent "${PI_ARGS[@]}"
herdr_run_prompt
herdr_finish
