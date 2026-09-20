#!/usr/bin/env bash
# pipeline-herdr.sh — Deterministic Research → Plan → Implement → Review pipeline.
#
# Runs four sequential agent stages, each in its own tab of one herdr workspace.
# Stages hand work forward via files in <repo>/.agent-work/. A strong model
# (default: claude/opus) does the planning; a cheap/local model does the
# token-heavy research and implementation (default: pi/dgx/qwen3.6-35b-mtp);
# review defaults to pi/dgx/qwen3.8-27b.
#
# Usage:
#   pipeline-herdr.sh <repo> "<task description>" [options]
#
# Resume a failed run (task may be omitted if .agent-work/task.md exists):
#   pipeline-herdr.sh <repo> --from-stage implement
#
# Options:
#   --research-kind <kind>    Agent kind (default: pi)
#   --research-model <model>  Model (default: dgx/qwen3.6-35b-mtp)
#   --research-timeout <ms>   (default: 3600000)
#   --plan-kind <kind>        (default: claude)
#   --plan-model <model>      (default: opus)
#   --plan-timeout <ms>       (default: 3600000)
#   --implement-kind <kind>   (default: pi)
#   --implement-model <model> (default: dgx/qwen3.6-35b-mtp)
#   --implement-timeout <ms>  (default: 10800000)
#   --review-kind <kind>      (default: pi)
#   --review-model <model>    (default: dgx/qwen3.8-27b)
#   --review-timeout <ms>     (default: 3600000)
#   --from-stage <stage>      Skip stages before this one (research|plan|implement|review)
#   --fresh                   Do not skip stages whose gate already passes
#   --close                   Close the herdr workspace when the pipeline succeeds
#   -h, --help                Show this help
#
# Artifacts (in <repo>/.agent-work/):
#   task.md        Task description (written by this script)
#   research.md    Research findings            (gate: exists, non-empty)
#   plan.md        Implementation plan          (gate: exists, non-empty)
#   results.md     Implementer report           (gate: "RESULTS: all-pass")
#   review.md      Review + fixes               (gate: "STATUS: clean" or "STATUS: open:<n>")
#   <stage>.transcript.md   Last 400 lines of each stage's terminal output
#   pipeline.log   Full run log
#
# Exit codes:
#   0  all stages clean
#   1  usage / environment error
#   10 research stage failed
#   11 plan stage failed
#   12 implement stage failed
#   13 review stage failed (no STATUS line produced)
#   14 pipeline finished but review left open issues (STATUS: open:<n>)
#
# Example:
#   pipeline-herdr.sh ~/code/myrepo "Add retry with backoff to the API client"
#   pipeline-herdr.sh ~/code/myrepo "Refactor config loader" \
#       --research-model opus --implement-model anthropic/claude-sonnet-4-5

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPTS_DIR="$SKILL_DIR/prompts"

# ── Defaults ─────────────────────────────────────────────────────────────────
RESEARCH_KIND="pi";       RESEARCH_MODEL="dgx/qwen3.6-35b-mtp";  RESEARCH_TIMEOUT=3600000
PLAN_KIND="claude";       PLAN_MODEL="opus";                     PLAN_TIMEOUT=3600000
IMPL_KIND="pi";           IMPL_MODEL="dgx/qwen3.6-35b-mtp";      IMPL_TIMEOUT=10800000
REVIEW_KIND="pi";         REVIEW_MODEL="dgx/qwen3.8-27b";        REVIEW_TIMEOUT=3600000
START_STAGE="research"
FRESH=false
CLOSE_WS=false

# ── Usage ────────────────────────────────────────────────────────────────────
usage() { sed -n '2,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ── Argument parsing ─────────────────────────────────────────────────────────
REPO=""
TASK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --research-kind)       RESEARCH_KIND="$2"; shift 2 ;;
        --research-model)      RESEARCH_MODEL="$2"; shift 2 ;;
        --research-timeout)    RESEARCH_TIMEOUT="$2"; shift 2 ;;
        --plan-kind)           PLAN_KIND="$2"; shift 2 ;;
        --plan-model)          PLAN_MODEL="$2"; shift 2 ;;
        --plan-timeout)        PLAN_TIMEOUT="$2"; shift 2 ;;
        --implement-kind)      IMPL_KIND="$2"; shift 2 ;;
        --implement-model)     IMPL_MODEL="$2"; shift 2 ;;
        --implement-timeout)   IMPL_TIMEOUT="$2"; shift 2 ;;
        --review-kind)         REVIEW_KIND="$2"; shift 2 ;;
        --review-model)        REVIEW_MODEL="$2"; shift 2 ;;
        --review-timeout)      REVIEW_TIMEOUT="$2"; shift 2 ;;
        --from-stage)          START_STAGE="$2"; shift 2 ;;
        --fresh)               FRESH=true; shift ;;
        --close)               CLOSE_WS=true; shift ;;
        -h|--help)             usage; exit 0 ;;
        -*)                    echo "ERROR: unknown option: $1" >&2; usage; exit 1 ;;
        *)
            if [[ -z "$REPO" ]]; then REPO="$1"; shift
            elif [[ -z "$TASK" ]]; then TASK="$1"; shift
            else echo "ERROR: unexpected argument: $1" >&2; exit 1; fi ;;
    esac
done

if [[ -z "$REPO" ]]; then
    echo "ERROR: <repo> is required." >&2; usage; exit 1
fi
if [[ ! -d "$REPO" ]]; then
    echo "ERROR: repo directory not found: $REPO" >&2; exit 1
fi
case "$START_STAGE" in
    research|plan|implement|review) ;;
    *) echo "ERROR: --from-stage must be research|plan|implement|review" >&2; exit 1 ;;
esac
for p in research plan implement review; do
    [[ -f "$PROMPTS_DIR/$p.md" ]] || { echo "ERROR: prompt file missing: $PROMPTS_DIR/$p.md" >&2; exit 1; }
done

REPO="$(cd "$REPO" && pwd)"
WORK="$REPO/.agent-work"
mkdir -p "$WORK"
exec > >(tee -a "$WORK/pipeline.log") 2>&1

# ── herdr server check ───────────────────────────────────────────────────────
command -v herdr >/dev/null 2>&1 || { echo "ERROR: herdr not found in PATH" >&2; exit 1; }
if ! herdr status >/dev/null 2>&1; then
    echo "[pipeline] herdr server not running — starting..."
    nohup herdr server > /tmp/herdr-server.log 2>&1 &
    for _ in $(seq 1 10); do
        sleep 1
        herdr status >/dev/null 2>&1 && break
    done
fi
herdr status >/dev/null 2>&1 || { echo "ERROR: herdr server not available (see /tmp/herdr-server.log)" >&2; exit 1; }

# ── Task file ────────────────────────────────────────────────────────────────
if [[ -n "$TASK" ]]; then
    printf '%s\n' "$TASK" > "$WORK/task.md"
    echo "[pipeline] task written to $WORK/task.md"
fi
[[ -s "$WORK/task.md" ]] || { echo "ERROR: no task given and $WORK/task.md is missing." >&2; exit 1; }

# ── Workspace ────────────────────────────────────────────────────────────────
WS_LABEL="pipeline-$(date +%Y%m%d-%H%M%S)"
WS="$(herdr workspace create --label "$WS_LABEL" --cwd "$REPO" | jq -r '.result.workspace.workspace_id')"
if [[ -z "$WS" || "$WS" == "null" ]]; then
    echo "ERROR: failed to create herdr workspace" >&2; exit 1
fi
echo "[pipeline] workspace: $WS_LABEL ($WS)"

trap 'echo "[pipeline] interrupted"; herdr notification show "Pipeline interrupted" --body "Workspace: $WS_LABEL" 2>/dev/null || true' INT

# ── Stage gates (mechanical checks only) ─────────────────────────────────────
gate_research()  { test -s "$WORK/research.md"; }
gate_plan()      { test -s "$WORK/plan.md"; }
gate_implement() { grep -q '^RESULTS: all-pass' "$WORK/results.md" 2>/dev/null; }
gate_review()    { grep -Eq '^STATUS: (clean|open:[0-9]+)$' "$WORK/review.md" 2>/dev/null; }

# ── Stage runner ─────────────────────────────────────────────────────────────
# run_stage <name> <kind> <model> <prompt_file> <timeout_ms> <gate_fn> <gate_desc>
run_stage() {
    local name="$1" kind="$2" model="$3" prompt_file="$4" timeout="$5" gate="$6" gate_desc="$7"
    local tab pane prompt text attempt

    echo ""
    echo "=== STAGE: $name ($kind / $model) ==="
    tab="$(herdr tab create --workspace "$WS" --label "$name" | jq -r '.result.tab.tab_id')"
    pane="$(herdr pane list --workspace "$WS" | jq -r '.result.panes[-1].pane_id')"
    if [[ -z "$pane" || "$pane" == "null" ]]; then
        echo "[pipeline] $name: failed to find pane for new tab" >&2
        return 1
    fi
    herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000 -- --model "$model"
    sleep 3

    prompt="$(cat "$prompt_file")"
    for attempt in 1 2; do
        text="$prompt"
        if [[ $attempt -gt 1 ]]; then
            text="$prompt

---
PREVIOUS ATTEMPT FAILED THE STAGE GATE.
Gate requirement: $gate_desc
Tail of your previous transcript:
-----
$(tail -n 80 "$WORK/$name.transcript.md" 2>/dev/null)
-----
Diagnose what went wrong and complete the work so the gate passes."
        fi
        echo "[pipeline] $name: attempt $attempt (timeout ${timeout}ms)"
        if ! herdr agent prompt "$name" "$text" --wait --timeout "$timeout"; then
            echo "[pipeline] $name: prompt wait returned an error (timeout or stall)"
        fi
        herdr agent read "$name" --source recent --lines 400 > "$WORK/$name.transcript.md" 2>/dev/null || true
        if "$gate"; then
            echo "[pipeline] $name: gate passed"
            return 0
        fi
        echo "[pipeline] $name: gate not met after attempt $attempt ($gate_desc)"
    done
    return 1
}

# ── Run pipeline ─────────────────────────────────────────────────────────────
notify() { herdr notification show "$1" --body "$2" --position top-right --sound "${3:-none}" 2>/dev/null || true; }
notify "Pipeline started" "$WS_LABEL — $(head -c 100 "$WORK/task.md")" request

die_stage() {  # <exit_code> <stage>
    echo ""
    echo "FATAL: stage '$2' failed. Workspace kept open: $WS_LABEL"
    echo "Inspect: $WORK/$2.transcript.md and $WORK/pipeline.log"
    echo "Resume:   $0 \"$REPO\" --from-stage $2"
    notify "Pipeline failed" "Stage $2 — workspace $WS_LABEL" request
    exit "$1"
}

start_index=0
case "$START_STAGE" in
    plan)      start_index=1 ;;
    implement) start_index=2 ;;
    review)    start_index=3 ;;
esac

idx=0
for stage in research plan implement review; do
    if [[ $idx -lt $start_index ]]; then
        echo "[pipeline] $stage: skipped (before --from-stage)"
    elif [[ "$FRESH" != "true" ]] && gate_$stage; then
        echo "[pipeline] $stage: gate already passes — skipped (use --fresh to force)"
    else
        case "$stage" in
            research)  run_stage research  "$RESEARCH_KIND" "$RESEARCH_MODEL" "$PROMPTS_DIR/research.md"  "$RESEARCH_TIMEOUT"  gate_research  "research.md exists and is non-empty"          || die_stage 10 research ;;
            plan)      run_stage plan      "$PLAN_KIND"     "$PLAN_MODEL"     "$PROMPTS_DIR/plan.md"      "$PLAN_TIMEOUT"      gate_plan      "plan.md exists and is non-empty"                || die_stage 11 plan ;;
            implement) run_stage implement "$IMPL_KIND"     "$IMPL_MODEL"     "$PROMPTS_DIR/implement.md" "$IMPL_TIMEOUT"      gate_implement "results.md ends with 'RESULTS: all-pass'"       || die_stage 12 implement ;;
            review)    run_stage review    "$REVIEW_KIND"   "$REVIEW_MODEL"   "$PROMPTS_DIR/review.md"    "$REVIEW_TIMEOUT"    gate_review    "review.md ends with a 'STATUS: ...' line"         || die_stage 13 review ;;
        esac
    fi
    idx=$((idx + 1))
done

# ── Final verdict ────────────────────────────────────────────────────────────
echo ""
echo "=== PIPELINE COMPLETE ==="
echo "Artifacts in $WORK:"
ls -la "$WORK"
echo ""
echo "--- review.md ---"
cat "$WORK/review.md"

if grep -q '^STATUS: open:' "$WORK/review.md" 2>/dev/null; then
    notify "Pipeline finished (open issues)" "Workspace $WS_LABEL — see review.md" request
    [[ "$CLOSE_WS" == "true" ]] && herdr workspace close "$WS" 2>/dev/null || true
    exit 14
fi

notify "Pipeline clean" "Workspace $WS_LABEL" done
[[ "$CLOSE_WS" == "true" ]] && herdr workspace close "$WS" 2>/dev/null || true
exit 0
