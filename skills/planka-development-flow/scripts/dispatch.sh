#!/usr/bin/env bash
#
# dispatch.sh — classical orchestrator for the planka-development-flow system.
#
# Polls the Planka dispatch board, claims eligible tickets, launches agentic
# implementer/reviewer sessions via herdr (or runagent+asb sandbox), verifies
# their work with hard gates, and captures their reports. Zero LLM in this
# script: the agent is the only fuzzy part.
#
# Usage:
#   dispatch.sh run         # implement + review + cleanup (the cron entry point)
#   dispatch.sh implement   # only the implementation phase
#   dispatch.sh review      # only the AI-review phase
#   dispatch.sh cleanup     # only worktree/branch cleanup for Done cards
#   dispatch.sh status      # board overview
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_DIR="$SCRIPT_DIR/prompts"
CONFIG=${PLANKA_DEVFLOW_CONFIG:-"$HOME/.config/planka-development-flow/config.env"}
LOCKFILE="${TMPDIR:-/tmp}/planka-devflow.lock"

[ -f "$CONFIG" ] || { echo "ERROR: config not found: $CONFIG" >&2; exit 2; }
# shellcheck disable=SC1090
source "$CONFIG"

# --- config validation: refuse to run with unfilled placeholders -------------
# Models: MODEL is the default for both roles; MODEL_IMPL / MODEL_REVIEW
# override it per role. At least one of the pair must resolve for each role.
MODEL="${MODEL:-}"
MODEL_IMPL="${MODEL_IMPL:-$MODEL}"
MODEL_REVIEW="${MODEL_REVIEW:-$MODEL}"
MISSING=""
for v in PLANKA_PROJECT PLANKA_BOARD LIST_INBOX LIST_READY LIST_CLAIMED \
         LIST_IN_PROGRESS LIST_READY_REVIEW LIST_AI_REVIEW LIST_HUMAN_REVIEW \
         LIST_DONE LIST_REJECTED FIELD_GROUP BASE_GROUP FIELD_PROJECT \
         FIELD_ATTEMPTS; do
  [ -n "${!v:-}" ] || MISSING="$MISSING $v"
done
if [ -n "$MISSING" ]; then
  echo "ERROR: incomplete config ($CONFIG) — set:$MISSING" >&2; exit 2
fi
if [ -z "$MODEL_IMPL" ] || [ -z "$MODEL_REVIEW" ]; then
  echo "ERROR: no model configured ($CONFIG) — set MODEL and/or MODEL_IMPL / MODEL_REVIEW" >&2; exit 2
fi

# Thinking levels: THINKING_IMPL / THINKING_REVIEW append a pi `:level` suffix
# to the resolved role model (off/minimal/low/medium/high/xhigh/max).
# An explicit `:suffix` already on the model string wins.
thinking_suffix() { # <model> <thinking> <role>
  local m=$1 t=$2 role=$3
  case "$t" in
    "") echo "$m"; return;;
    off|minimal|low|medium|high|xhigh|max)
      if printf '%s' "$m" | grep -q ':'; then echo "$m"; else echo "$m:$t"; fi;;
    *) echo "ERROR: bad $role thinking level '$t' (want off/minimal/low/medium/high/xhigh/max)" >&2; exit 2;;
  esac
}
MODEL_IMPL=$(thinking_suffix "$MODEL_IMPL" "${THINKING_IMPL:-}" impl)
MODEL_REVIEW=$(thinking_suffix "$MODEL_REVIEW" "${THINKING_REVIEW:-}" review)

# --- Runner config -----------------------------------------------------------
: "${RUNNER:=herdr}"          # herdr | runagent
: "${AGENT_IMPL:=impl}"       # runagent profile name for implementer
: "${AGENT_REVIEW:=review}"   # runagent profile name for reviewer
: "${RUNAGENT:=runagent}"     # command name or absolute path

if [ "$RUNNER" = "runagent" ]; then
  # Prefer the explicit RUNAGENT path; fall back to PATH lookup.
  if [ -x "$RUNAGENT" ]; then
    : # RUNAGENT is already an executable path
  elif command -v "$RUNAGENT" >/dev/null 2>&1; then
    RUNAGENT="$(command -v "$RUNAGENT")"
  else
    echo "ERROR: RUNNER=runagent but RUNAGENT='$RUNAGENT' not found" >&2; exit 2
  fi
  # Preflight: check if asb supports --ro-bind (reviewer read-only worktree).
  # Log a warning once per run if --ro-bind is absent (degraded mode).
  _ASB_SUPPORTS_RO_BIND=true
  if command -v asb >/dev/null 2>&1; then
    if ! asb --help 2>&1 | grep -q -- '--ro-bind'; then
      _ASB_SUPPORTS_RO_BIND=false
      echo "WARNING: asb does not support --ro-bind (reviewer worktree will not be read-only; G3 backstop still applies)" >&2
    fi
  else
    echo "WARNING: asb not found on PATH; reviewer worktree will not be read-only (G3 backstop still applies)" >&2
  fi
else
  [ -x "$HERDR_RUN" ] || { echo "ERROR: HERDR_RUN is not executable: $HERDR_RUN" >&2; exit 2; }
fi

# Defaults for anything the config leaves unset
: "${MAX_PARALLEL:=2}"
: "${MAX_ATTEMPTS:=3}"
: "${CARD_TIMEOUT:=3600}"
: "${POLL_INTERVAL:=20}"
: "${WT_ROOT:=$HOME/worktrees}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }

# ---------------------------------------------------------------------------
# plnk helpers (all best-effort; failures return empty / non-zero)
# ---------------------------------------------------------------------------
card_list()   { plnk card get "$1" --output json 2>/dev/null | jq -r '.data.listId // empty'; }
card_title()  { plnk card get "$1" --output json 2>/dev/null | jq -r '.data.name // empty'; }
card_count()  { plnk card list --list "$1" --output json 2>/dev/null | jq -r '.data | length' 2>/dev/null || echo 0; }
get_field() { # <card> <fieldId>
  plnk card field list "$1" --output json 2>/dev/null \
    | jq -r --arg id "$2" '[.data[] | select(.customFieldId==$id) | .content] | first // empty'
}
set_field() { # <card> <fieldName> <value>
  plnk card field set "$1" --group "$FIELD_GROUP" --field "$2" --value "$3" --output json >/dev/null 2>&1
}
add_comment() { # <card> <text>
  plnk comment create --card "$1" --text "$2" --output json >/dev/null 2>&1
}
move_card() { # <card> <listId>
  plnk card move "$1" --to-list "$2" --output json >/dev/null 2>&1
}
comment_count() { # <card>
  plnk comment list --card "$1" --output json 2>/dev/null | jq -r '.data | length' 2>/dev/null || echo 0
}

proj_key() { # shell-safe key: non-alphanumeric -> _  (my-app -> my_app)
  echo "${1//[^a-zA-Z0-9]/_}"
}
proj_repo() { # <projectName> -> repo path (non-zero if unknown)
  local k="PROJ_$(proj_key "$1")_repo" v
  v=${!k:-}
  [ -n "$v" ] && echo "$v" || return 1
}
proj_base_ref() { local k="PROJ_$(proj_key "$1")_base_ref"; echo "${!k:-main}"; }
proj_test_cmd() { local k="PROJ_$(proj_key "$1")_test"; echo "${!k:-}"; }

# ---------------------------------------------------------------------------
# herdr helpers
# ---------------------------------------------------------------------------
ws_id_by_label() { # <label> — newest workspace (highest number) with this label
  herdr workspace list 2>/dev/null \
    | jq -r --arg l "$1" '(.result // .) | .workspaces[]? | select(.label==$l) | [.number, .workspace_id] | @tsv' 2>/dev/null \
    | sort -n | tail -1 | cut -f2
}
agent_by_ws() { # <workspaceId> — first agent in this workspace that has a name
  herdr agent list 2>/dev/null \
    | jq -r --arg ws "$1" '(.result // .) | .agents[]? | select(.workspace_id==$ws) | .name // empty | select(. != "")' 2>/dev/null \
    | head -1
}
close_ws() { # <label>
  local ws
  ws=$(ws_id_by_label "$1")
  [ -n "$ws" ] && herdr workspace close "$ws" >/dev/null 2>&1
  return 0
}
capture_report() { # <card> <wsLabel>
  # Post the agent's final transcript output as a card comment.
  # The pipeline owns reporting: agents are not trusted to post it.
  local agent text ws
  ws=$(ws_id_by_label "$2")
  [ -z "$ws" ] && { log "capture $2: no workspace found"; return 1; }
  agent=$(agent_by_ws "$ws")
  [ -z "$agent" ] && { log "capture $2: workspace $ws has no named agent"; return 1; }
  # The card move lands a beat before the agent's terminal buffer settles, so
  # retry the read a few times rather than racing the flush.
  local i
  for i in 1 2 3 4 5; do
    text=$(herdr agent read "$agent" --source recent --lines 200 2>/dev/null | head -c 4000)
    [ -n "$text" ] && break
    sleep 5
  done
  [ -z "$text" ] && { log "capture $2: agent $agent read empty after retries"; return 1; }
  add_comment "$1" "## Report (auto-captured by dispatcher — agent did not post its own comment)

$text"
}

# ---------------------------------------------------------------------------
# agent launch + wait
# ---------------------------------------------------------------------------
run_agent() { # <card> <wsLabel> <worktree> <promptFile> <baseRef> <model> <reviewer?>
  local card=$1 label=$2 wt=$3 promptfile=$4 baseref=$5 model=$6 is_reviewer=${7:-false}
  local prompt scratch_dir="" ro_bind_args=""

  prompt=$(sed \
    -e "s/__CARD__/$card/g" \
    -e "s/__BASE_REF__/$baseref/g" \
    -e "s/__LIST_READY__/$LIST_READY/g" \
    -e "s/__LIST_READY_REVIEW__/$LIST_READY_REVIEW/g" \
    -e "s/__LIST_HUMAN_REVIEW__/$LIST_HUMAN_REVIEW/g" \
    "$promptfile")

  if [ "$RUNNER" = "herdr" ]; then
    # --- herdr runner (regression: byte-identical to pre-change invocation) ---
    "$HERDR_RUN" -m "$model" -p "$prompt" -c "$wt" -l "$label" \
      -w "$CARD_TIMEOUT_MS" --no-wait >/dev/null 2>&1
  else
    # --- runagent runner ---
    local profile="$AGENT_IMPL"
    [ "$is_reviewer" = true ] && profile="$AGENT_REVIEW"

    # Reviewer: create scratch dir and pass --ro-bind + -c scratch
    if [ "$is_reviewer" = true ]; then
      scratch_dir="$WT_ROOT/scratch/$card"
      mkdir -p "$scratch_dir"
      ro_bind_args="--ro-bind $wt"
    fi

    local model_arg=""
    [ -n "$model" ] && model_arg="-m $model"

    # shellcheck disable=SC2086
    "$RUNAGENT" "$profile" -p "$prompt" -c "$wt" --label "$label" --no-wait --keep \
      $model_arg $ro_bind_args ${scratch_dir:+-c "$scratch_dir"} >/dev/null 2>&1
  fi
}

# ---------------------------------------------------------------------------
# idle rescue — the agent ended its turn without moving the card (observed in
# the wild: report posted / verdict written, final `plnk card move` dropped).
# The dispatcher completes the move from deterministic evidence; gates remain
# the authority. Grace period avoids racing agent startup / brief idle states.
# ---------------------------------------------------------------------------
agent_idle() { # <wsLabel> — 0 if the workspace's agent exists and is not working
  local ws agent status
  ws=$(ws_id_by_label "$1")
  [ -n "$ws" ] || return 1
  agent=$(agent_by_ws "$ws")
  [ -n "$agent" ] || return 1
  status=$(herdr agent list 2>/dev/null \
    | jq -r --arg a "$agent" '(.result // .) | .agents[]? | select(.name==$a) | .agent_status // empty' 2>/dev/null \
    | head -1)
  [ -n "$status" ] && [ "$status" != "working" ]
}

recent_transcript() { # <wsLabel> [lines]
  local ws agent
  ws=$(ws_id_by_label "$1")
  [ -n "$ws" ] || return 1
  agent=$(agent_by_ws "$ws")
  [ -n "$agent" ] || return 1
  herdr agent read "$agent" --source recent --lines "${2:-400}" 2>/dev/null | head -c 8000
}

rescue_implement() { # <card> <wsLabel> — always moves the card (0)
  local card=$1 label=$2 text wt baseref commits
  wt="$WT_ROOT/${PROJECT_OF[$card]}/$card"
  baseref=$(proj_base_ref "${PROJECT_OF[$card]}")
  text=$(recent_transcript "$label" 400)
  if grep -q "STATUS: FAILED" <<<"$text"; then
    add_comment "$card" "🔁 Dispatcher rescue: implementer ended its turn (STATUS: FAILED) without moving the card — moving to Ready."
    move_card "$card" "$LIST_READY"
    return 0
  fi
  commits=$(git -C "$wt" rev-list --count "$baseref..HEAD" 2>/dev/null || echo 0)
  if [ "$commits" -ge 1 ]; then
    add_comment "$card" "🔁 Dispatcher rescue: implementer ended its turn with $commits commit(s) but no card move — moving to Ready for Review (gates still apply)."
    move_card "$card" "$LIST_READY_REVIEW"
    return 0
  fi
  add_comment "$card" "⛔ Dispatcher rescue: implementer ended its turn with no commits and no card move — treating as failure."
  move_card "$card" "$LIST_READY"
  return 0
}

rescue_review() { # <card> <wsLabel> — 0 if a move was made, 1 if no verdict found
  local card=$1 label=$2 text
  text=$(recent_transcript "$label" 500)
  if grep -q "VERDICT: APPROVE" <<<"$text"; then
    add_comment "$card" "🔁 Dispatcher rescue: reviewer ended its turn with VERDICT: APPROVE but no card move — moving to Human Review."
    move_card "$card" "$LIST_HUMAN_REVIEW"
    return 0
  fi
  if grep -q "VERDICT: CHANGES REQUESTED" <<<"$text"; then
    add_comment "$card" "🔁 Dispatcher rescue: reviewer ended its turn with VERDICT: CHANGES REQUESTED but no card move — moving to Ready."
    move_card "$card" "$LIST_READY"
    return 0
  fi
  log "rescue review $card: agent idle but no VERDICT line — no move"
  return 1
}

wait_for_card() { # <card> <listItLeaves> [timeout] [wsLabel kind] -> 0 left, 1 timeout
  local card=$1 from=$2 timeout=${3:-$CARD_TIMEOUT} label=${4:-} kind=${5:-}
  local start now
  start=$(date +%s)
  while :; do
    [ "$(card_list "$card")" != "$from" ] && return 0
    now=$(date +%s)
    [ $((now - start)) -ge "$timeout" ] && return 1
    if [ -n "$label" ] && [ $((now - start)) -ge 120 ]; then
      if agent_idle "$label"; then
        if [ "$kind" = impl ]; then
          rescue_implement "$card" "$label" && return 0
        elif [ "$kind" = review ]; then
          rescue_review "$card" "$label" && return 0
        fi
      fi
    fi
    sleep "$POLL_INTERVAL"
  done
}

# ---------------------------------------------------------------------------
# bounce / reject
# ---------------------------------------------------------------------------
bounce() { # <card> <wsLabel> <reason>
  local card=$1 label=$2 reason=$3
  local attempts
  attempts=$(get_field "$card" "$FIELD_ATTEMPTS")
  attempts=${attempts:-0}
  attempts=$((attempts + 1))
  set_field "$card" "attempts" "$attempts"
  add_comment "$card" "$reason"
  if [ "$attempts" -ge "$MAX_ATTEMPTS" ]; then
    add_comment "$card" "🛑 Max attempts ($MAX_ATTEMPTS) reached — moving to Rejected."
    move_card "$card" "$LIST_REJECTED"
    log "card $card REJECTED after $attempts attempts"
  else
    move_card "$card" "$LIST_READY"
    log "card $card bounced back to Ready (attempt $attempts/$MAX_ATTEMPTS)"
  fi
  close_ws "$label"
}

# ---------------------------------------------------------------------------
# implementation phase
# ---------------------------------------------------------------------------
declare -A COMMENTS_BEFORE=()
declare -A PROJECT_OF=()

eligible_cards() { # cards in Ready with known project and attempts < max
  local c p a
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    p=$(get_field "$c" "$FIELD_PROJECT")
    a=$(get_field "$c" "$FIELD_ATTEMPTS")
    [ -n "$p" ] || { log "skip $c: no project field"; continue; }
    proj_repo "$p" >/dev/null || { log "skip $c: unknown project '$p'"; continue; }
    [ "${a:-0}" -lt "$MAX_ATTEMPTS" ] || { log "skip $c: attempts exhausted"; continue; }
    echo "$c"
  done < <(plnk card list --list "$LIST_READY" --output json 2>/dev/null | jq -r '.data[].id')
}

claim_and_prepare() { # <card> — claim, worktree, In Progress, dispatch comment
  local card=$1 project repo wt baseref
  project=$(get_field "$card" "$FIELD_PROJECT")
  repo=$(proj_repo "$project") || return 1
  baseref=$(proj_base_ref "$project")
  wt="$WT_ROOT/$project/$card"

  move_card "$card" "$LIST_CLAIMED" || return 1
  if [ ! -d "$wt" ]; then
    if git -C "$repo" show-ref --verify --quiet "refs/heads/ai/$card"; then
      git -C "$repo" worktree add "$wt" "ai/$card" >/dev/null 2>&1 || return 1
    else
      git -C "$repo" worktree add "$wt" -b "ai/$card" "$baseref" >/dev/null 2>&1 || return 1
    fi
  fi
  move_card "$card" "$LIST_IN_PROGRESS" || return 1
  add_comment "$card" "🚀 Dispatched ($project): worktree $wt, branch ai/$card (base $baseref)."
  COMMENTS_BEFORE[$card]=$(comment_count "$card")
  PROJECT_OF[$card]=$project
  return 0
}

finish_implementation() { # <card>
  local card=$1 project repo wt baseref test_cmd
  project=${PROJECT_OF[$card]}
  repo=$(proj_repo "$project")
  baseref=$(proj_base_ref "$project")
  wt="$WT_ROOT/$project/$card"

  if ! wait_for_card "$card" "$LIST_IN_PROGRESS" "" "impl-$card" impl; then
    bounce "$card" "impl-$card" "⛔ Dispatcher: implementation timed out after ${CARD_TIMEOUT}s."
    return 1
  fi

  local list
  list=$(card_list "$card")
  if [ "$list" = "$LIST_READY" ]; then
    capture_report "$card" "impl-$card" || true
    bounce "$card" "impl-$card" "🔁 Bounced: implementer reported failure."
    return 1
  fi
  if [ "$list" != "$LIST_READY_REVIEW" ]; then
    add_comment "$card" "⚠️ Dispatcher: card in unexpected list after implementation."
    bounce "$card" "impl-$card" "⛔ Dispatcher: unexpected card state after implementation."
    return 1
  fi

  # --- G1: commits exist -------------------------------------------------
  local commits
  commits=$(git -C "$wt" rev-list --count "$baseref..HEAD" 2>/dev/null || echo 0)
  if [ "$commits" -lt 1 ]; then
    bounce "$card" "impl-$card" "⛔ Gate G1 failed: no new commits on ai/$card."
    return 1
  fi

  # --- G2: tests pass ------------------------------------------------------
  test_cmd=$(proj_test_cmd "$project")
  if [ -n "$test_cmd" ]; then
    local testlog
    testlog=$(mktemp)
    if ! ( cd "$wt" && eval "$test_cmd" ) >"$testlog" 2>&1; then
      add_comment "$card" "⛔ Gate G2 failed: tests failed.
$(tail -15 "$testlog")"
      rm -f "$testlog"
      bounce "$card" "impl-$card" "⛔ Gate G2 failed: test command failed (see comment)."
      return 1
    fi
    rm -f "$testlog"
  fi

  # --- G3: scope / protected files -----------------------------------------
  local files f hard_hits="" soft_hits="" p hk sk
  hk="PROJ_$(proj_key "$project")_hard"
  sk="PROJ_$(proj_key "$project")_soft"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    for p in ${!hk:-}; do
      # shellcheck disable=SC2254
      case "$f" in $p) hard_hits="$hard_hits $f"; break;; esac
    done
    if [[ "$hard_hits" != *" $f"* ]]; then
      for p in ${!sk:-}; do
        # shellcheck disable=SC2254
        case "$f" in $p) soft_hits="$soft_hits $f"; break;; esac
      done
    fi
  done < <(git -C "$wt" diff --name-only "$baseref..HEAD")

  if [ -n "$hard_hits" ]; then
    add_comment "$card" "⛔ Gate G3 (hard) failed: diff touches protected files:$hard_hits"
    bounce "$card" "impl-$card" "⛔ Gate G3 (hard) failed: touched protected files:$hard_hits"
    return 1
  fi
  if [ -n "$soft_hits" ]; then
    add_comment "$card" "⚠️ Gate G3 (soft): diff touches files that default to do-not-touch:$soft_hits — human review attention required."
  fi

  # --- report: agent's own comment, else auto-capture -----------------------
  if [ "$(comment_count "$card")" -le "${COMMENTS_BEFORE[$card]}" ]; then
    capture_report "$card" "impl-$card" \
      || add_comment "$card" "⚠️ Dispatcher: no implementer report found and transcript capture failed."
  fi

  add_comment "$card" "✅ Gates passed (G1: $commits commit(s), G2: tests ok, G3: scope ok). Ready for AI review."
  close_ws "impl-$card"
  log "card $card → Ready for Review"
  return 0
}

phase_implement() {
  log "phase: implement (max parallel: $MAX_PARALLEL)"
  local cards=() c i=0
  while IFS= read -r c; do cards+=("$c"); done < <(eligible_cards)
  [ ${#cards[@]} -eq 0 ] && { log "no eligible cards in Ready"; return 0; }

  local dispatched=()
  for c in "${cards[@]}"; do
    [ $i -ge "$MAX_PARALLEL" ] && break
    if claim_and_prepare "$c"; then
      dispatched+=("$c")
      i=$((i + 1))
    else
      log "card $c: claim/prepare failed, skipped"
      move_card "$c" "$LIST_READY" 2>/dev/null || true
    fi
  done
  [ ${#dispatched[@]} -eq 0 ] && return 0
  log "launched ${#dispatched[@]} implementer(s): ${dispatched[*]}"

  local p br
  for c in "${dispatched[@]}"; do
    p=${PROJECT_OF[$c]}
    br=$(proj_base_ref "$p")
    run_agent "$c" "impl-$c" "$WT_ROOT/$p/$c" "$PROMPT_DIR/implementer.txt" "$br" "$MODEL_IMPL" &
  done
  wait

  for c in "${dispatched[@]}"; do
    finish_implementation "$c" || true
  done
}

# ---------------------------------------------------------------------------
# AI review phase
# ---------------------------------------------------------------------------
review_card() { # <card>
  local card=$1 project repo wt baseref
  project=$(get_field "$card" "$FIELD_PROJECT")
  [ -n "$project" ] || { add_comment "$card" "⛔ Dispatcher: no project field — cannot review."; return 1; }
  repo=$(proj_repo "$project") || { add_comment "$card" "⛔ Dispatcher: unknown project '$project'."; return 1; }
  baseref=$(proj_base_ref "$project")
  wt="$WT_ROOT/$project/$card"
  [ -d "$wt" ] || { add_comment "$card" "⛔ Dispatcher: no worktree for review."; move_card "$card" "$LIST_READY"; return 1; }

  move_card "$card" "$LIST_AI_REVIEW" || return 1
  add_comment "$card" "🔍 Picked up for AI review."
  local before
  before=$(comment_count "$card")

  run_agent "$card" "review-$card" "$wt" "$PROMPT_DIR/reviewer.txt" "$baseref" "$MODEL_REVIEW" true
  if ! wait_for_card "$card" "$LIST_AI_REVIEW" "" "review-$card" review; then
    add_comment "$card" "⛔ Dispatcher: review timed out after ${CARD_TIMEOUT}s — returning to Ready for Review."
    move_card "$card" "$LIST_READY_REVIEW"
    close_ws "review-$card"
    return 1
  fi

  # Reviewer report: agent's own comment, else auto-capture
  if [ "$(comment_count "$card")" -le "$before" ]; then
    capture_report "$card" "review-$card" \
      || add_comment "$card" "⚠️ Dispatcher: no review verdict found and transcript capture failed."
  fi

  local list
  list=$(card_list "$card")
  case "$list" in
    "$LIST_HUMAN_REVIEW") add_comment "$card" "✅ AI review: APPROVE — awaiting human review." ;;
    "$LIST_READY")        add_comment "$card" "🔁 AI review: CHANGES REQUESTED — back to Ready for re-implementation." ;;
    *)                    add_comment "$card" "⚠️ Dispatcher: unexpected list after AI review." ;;
  esac
  close_ws "review-$card"
  log "card $card: review done (now in list $list)"
  return 0
}

phase_review() {
  log "phase: review (max parallel: $MAX_PARALLEL)"
  local cards=() c
  while IFS= read -r c; do
    [ -n "$c" ] && { get_field "$c" "$FIELD_PROJECT" | grep -q . && cards+=("$c"); }
  done < <(plnk card list --list "$LIST_READY_REVIEW" --output json 2>/dev/null | jq -r '.data[].id')
  [ ${#cards[@]} -eq 0 ] && { log "no cards in Ready for Review"; return 0; }

  local i=0 started=()
  for c in "${cards[@]}"; do
    [ $i -ge "$MAX_PARALLEL" ] && break
    if review_card "$c" & then started+=("$c"); fi
    i=$((i + 1))
  done
  wait
  log "review phase complete"
}

# ---------------------------------------------------------------------------
# cleanup phase — worktrees/branches of Done cards
# ---------------------------------------------------------------------------
phase_cleanup() {
  log "phase: cleanup (Done cards)"
  local c p repo wt
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    p=$(get_field "$c" "$FIELD_PROJECT")
    [ -n "$p" ] || continue
    repo=$(proj_repo "$p") || continue
    wt="$WT_ROOT/$p/$c"
    if [ -d "$wt" ]; then
      git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 && log "removed worktree $wt"
    fi
    git -C "$repo" branch -D "ai/$c" >/dev/null 2>&1 && log "deleted branch ai/$c"
  done < <(plnk card list --list "$LIST_DONE" --output json 2>/dev/null | jq -r '.data[].id')
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------
cmd_status() {
  echo "Dispatch board: $PLANKA_BOARD"
  local pair
  for pair in \
    "Inbox:$LIST_INBOX" "Ready:$LIST_READY" "Claimed:$LIST_CLAIMED" \
    "In Progress:$LIST_IN_PROGRESS" "Ready for Review:$LIST_READY_REVIEW" \
    "In AI Review:$LIST_AI_REVIEW" "Human Review:$LIST_HUMAN_REVIEW" \
    "Done:$LIST_DONE" "Rejected:$LIST_REJECTED"; do
    printf "  %-18s %s\n" "${pair%%:*}" "$(card_count "${pair#*:}")"
  done
}

# ---------------------------------------------------------------------------
# main — locked so overlapping cron runs are no-ops
# ---------------------------------------------------------------------------
main() {
  local cmd=${1:-run}
  if [ "$cmd" = "status" ]; then
    cmd_status
    return 0
  fi

  exec 9>"$LOCKFILE"
  if ! flock -n 9; then
    log "another dispatch run is in progress — exiting"
    return 0
  fi

  case "$cmd" in
    run)       phase_implement; phase_review; phase_cleanup ;;
    implement) phase_implement ;;
    review)    phase_review ;;
    cleanup)   phase_cleanup ;;
    *) echo "usage: dispatch.sh {run|implement|review|cleanup|status}" >&2; return 2 ;;
  esac
  log "dispatch run complete"
}

main "$@"
