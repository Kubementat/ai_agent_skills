#!/usr/bin/env bash
# run-opencode-herdr.sh — Launch an opencode agent inside a herdr terminal workspace.
# Run with --help for usage and examples.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-common.sh"
# shellcheck disable=SC2034
AGENT_KIND="opencode"
# shellcheck disable=SC2034
AGENT_PREFIX="oc"
# shellcheck disable=SC2034
LABEL_PREFIX="opencode"
OPENCODE_AGENT=""
AUTO=false
usage() {
    cat <<'USAGE'
Usage: run-opencode-herdr.sh -m <model> -p "<prompt>" [options]
Launch an opencode agent inside a herdr terminal workspace, submit a task,
wait for completion, and print the output.
Options:
  -m, --model <model>              Model (required), e.g. anthropic/claude-sonnet-4-5
  -p, --prompt <prompt>            Task prompt (required)
  -w, --timeout <ms>               Wait timeout (default: 120000)
  -n, --name <name>                Agent name (default: auto-generated)
  -c, --cwd <path>                 Working directory (default: current dir)
  -l, --label <label>              Workspace label (default: based on model)
  -nk, --no-keep                   Close workspace after completion
  -nw, --no-wait                   Fire-and-forget: exit after prompting
  -h, --help                       Show this help message
      --agent <name>               Predefined opencode agent (see `opencode agent list`)
      --auto                       Auto-approve permissions not explicitly denied
Examples:
  run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -p "Explain src/main.ts"
  run-opencode-herdr.sh -m "google/gemini-2.5-pro" -p "Run tests" --auto --no-keep
USAGE
}
[[ $# -eq 0 ]] && usage && exit 0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)  OPENCODE_AGENT="$2"; shift 2 ;;
        --auto)   AUTO=true; shift ;;
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
OC_ARGS=("--model" "$MODEL")
[[ -n "$OPENCODE_AGENT" ]] && OC_ARGS+=("--agent" "$OPENCODE_AGENT")
[[ "$AUTO" == true ]] && OC_ARGS+=("--auto")
herdr_start_agent "${OC_ARGS[@]}"
herdr_run_prompt
herdr_finish
