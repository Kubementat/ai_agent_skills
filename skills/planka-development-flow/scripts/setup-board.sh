#!/usr/bin/env bash
#
# setup-board.sh — bootstrap the Planka board for planka-development-flow.
#
# Creates (or reuses, by name) the project, board, the 9 lists, and the
# "Dispatch" base field group with its project/attempts fields. Then writes
# a ready-to-edit config.env for dispatch.sh.
#
# Idempotent: safe to re-run. Never overwrites an existing config.env.
#
# Prereq: plnk on PATH and authenticated (see the plnk-cli skill):
#   plnk auth login --server <your planka url> --email ... --password ...
#   plnk auth status
#
# Usage:
#   setup-board.sh [--project NAME] [--board NAME] [--config PATH]
#     --project  project name            (default: AI-Orchestration)
#     --board    board name              (default: Dispatch Board)
#     --config   where to write config   (default: ~/.config/planka-development-flow/config.env)
#
set -euo pipefail

PROJECT_NAME="AI-Orchestration"
BOARD_NAME="Dispatch Board"
WT_ROOT="$HOME/worktrees"
CONFIG="${PLANKA_DEVFLOW_CONFIG:-$HOME/.config/planka-development-flow/config.env}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_NAME=$2; shift 2;;
    --board)   BOARD_NAME=$2; shift 2;;
    --config)  CONFIG=$2; shift 2;;
    -h|--help) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

log() { echo "[setup] $*" >&2; }

command -v plnk >/dev/null 2>&1 || { echo "ERROR: plnk not found on PATH" >&2; exit 2; }
command -v jq   >/dev/null 2>&1 || { echo "ERROR: jq not found on PATH" >&2; exit 2; }

# --- preflight: authenticated? ------------------------------------------------
if ! plnk project list --output json >/dev/null 2>&1; then
  echo "ERROR: plnk is not authenticated. Run: plnk auth login --server <planka-url> ..." >&2
  exit 2
fi

json_id() { jq -r '.data.id // empty'; }
find_id() { jq -r '.data[0].id // empty'; }

# --- project -------------------------------------------------------------------
log "project: $PROJECT_NAME"
PROJECT_ID=$(plnk project find --name "$PROJECT_NAME" --output json | find_id)
if [ -z "$PROJECT_ID" ]; then
  log "  creating"
  PROJECT_ID=$(plnk project create --name "$PROJECT_NAME" --output json | json_id)
fi
log "  id: $PROJECT_ID"

# --- board ---------------------------------------------------------------------
log "board: $BOARD_NAME"
BOARD_ID=$(plnk board find --project "$PROJECT_ID" --name "$BOARD_NAME" --output json | find_id)
if [ -z "$BOARD_ID" ]; then
  log "  creating"
  BOARD_ID=$(plnk board create --project "$PROJECT_ID" --name "$BOARD_NAME" --output json | json_id)
fi
log "  id: $BOARD_ID"

# --- lists (left to right) -------------------------------------------------------
LIST_NAMES=(Inbox Ready Claimed "In Progress" "Ready for Review" "In AI Review" "Human Review" Done Rejected)
LIST_IDS=()
for name in "${LIST_NAMES[@]}"; do
  id=$(plnk list find --board "$BOARD_ID" --name "$name" --output json | find_id)
  if [ -z "$id" ]; then
    log "  creating list: $name"
    id=$(plnk list create --board "$BOARD_ID" --name "$name" --output json | json_id)
  fi
  LIST_IDS+=("$id")
  log "  list '$name': $id"
done

# Planka inserts new lists at the FRONT (smallest position), so created boards
# come out reversed. Normalize the left-to-right order explicitly (idempotent —
# also repairs boards created by older versions of this script).
LIST_POSITIONS=(65536 131072 262144 524288 1048576 2097152 4194304 8388608 16777216)
for idx in "${!LIST_IDS[@]}"; do
  if ! plnk list update "${LIST_IDS[$idx]}" --position "${LIST_POSITIONS[$idx]}" --output json --yes >/dev/null 2>&1; then
    log "  WARN: could not set position for '${LIST_NAMES[$idx]}'"
  fi
done
log "  list order normalized (left to right)"

# --- base field group ----------------------------------------------------------
log "base field group: Dispatch"
BASE_GROUP=$(plnk field-group find --project "$PROJECT_ID" --name "Dispatch" --output json | find_id)
if [ -z "$BASE_GROUP" ]; then
  log "  creating"
  BASE_GROUP=$(plnk field-group create --project "$PROJECT_ID" --name "Dispatch" --output json | json_id)
fi
log "  id: $BASE_GROUP"

# --- fields ----------------------------------------------------------------------
field_id() { # <name> [show-on-front]
  local name=$1 front=${2:-} id
  id=$(plnk field find --base-group "$BASE_GROUP" --name "$name" --output json | find_id)
  if [ -z "$id" ]; then
    if [ -n "$front" ]; then
      log "  creating field: $name (show on front)"
      id=$(plnk field create --base-group "$BASE_GROUP" --name "$name" --show-on-front --output json | json_id)
    else
      log "  creating field: $name"
      id=$(plnk field create --base-group "$BASE_GROUP" --name "$name" --output json | json_id)
    fi
  fi
  echo "$id"
}
FIELD_PROJECT=$(field_id "project" yes)
FIELD_ATTEMPTS=$(field_id "attempts")
log "  field 'project':  $FIELD_PROJECT"
log "  field 'attempts': $FIELD_ATTEMPTS"

# --- agent launcher detection (best effort) --------------------------------------
HERDR_RUN=""
for cand in \
  "$HOME/.pi/agent/skills/herdr-cli/scripts/run-pi-herdr.sh" \
  "$HOME/.pi/agent/npm/node_modules/herdr-cli/scripts/run-pi-herdr.sh" \
  "$HOME/.agents/skills/herdr-cli/scripts/run-pi-herdr.sh"; do
  [ -x "$cand" ] && { HERDR_RUN=$cand; break; }
done

# --- config ----------------------------------------------------------------------
SNIPPET_FILE=$(mktemp)
trap 'rm -f "$SNIPPET_FILE"' EXIT

if [ -f "$CONFIG" ]; then
  log "config already exists — NOT overwriting: $CONFIG"
  log "merge the IDs below into your existing config:"
else
  mkdir -p "$(dirname "$CONFIG")"
  log "writing config: $CONFIG"
fi

cat > "$SNIPPET_FILE" <<EOF
# planka-development-flow dispatcher config
# Sourced by dispatch.sh — plain shell variables, no parser needed.
# Generated by setup-board.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ).

# --- Planka board ($PROJECT_NAME / $BOARD_NAME) ---
PLANKA_PROJECT=$PROJECT_ID
PLANKA_BOARD=$BOARD_ID

# --- Lists ($BOARD_NAME) ---
LIST_INBOX=${LIST_IDS[0]}
LIST_READY=${LIST_IDS[1]}
LIST_CLAIMED=${LIST_IDS[2]}
LIST_IN_PROGRESS=${LIST_IDS[3]}
LIST_READY_REVIEW=${LIST_IDS[4]}
LIST_AI_REVIEW=${LIST_IDS[5]}
LIST_HUMAN_REVIEW=${LIST_IDS[6]}
LIST_DONE=${LIST_IDS[7]}
LIST_REJECTED=${LIST_IDS[8]}

# --- Custom fields (Dispatch base group) ---
FIELD_GROUP=Dispatch
BASE_GROUP=$BASE_GROUP
FIELD_PROJECT=$FIELD_PROJECT
FIELD_ATTEMPTS=$FIELD_ATTEMPTS

# --- Dispatcher behavior ---
MAX_PARALLEL=2          # max tickets in flight per dispatch run
MAX_ATTEMPTS=3          # bounce limit, then Rejected
CARD_TIMEOUT=3600       # seconds to wait for one agent (polling)
POLL_INTERVAL=20        # seconds between card-state polls

# --- Agent launch ---
# Empty strings = not detected / not set yet — dispatch.sh refuses to run until set.
HERDR_RUN="${HERDR_RUN}"
MODEL=""                        # default herdr/pi model, e.g. <provider>/<model>
MODEL_IMPL=""                   # optional: override for the implementer agent
MODEL_REVIEW=""                 # optional: override for the reviewer agent
THINKING_IMPL=""                # optional: pi thinking level for the implementer
THINKING_REVIEW=""              # optional: pi thinking level for the reviewer
# Thinking levels: off / minimal / low / medium / high / xhigh / max

# --- Runner selection ---
# RUNNER=herdr   — use the legacy run-pi-herdr.sh (default, current behavior)
# RUNNER=runagent — use runagent + asb bubblewrap sandbox (sandboxed agents)
RUNNER=herdr
# For RUNNER=runagent:
# RUNAGENT=runagent   # command name (PATH) or absolute path to the runagent script
# AGENT_IMPL=impl     # runagent profile name for the implementer agent
# AGENT_REVIEW=review # runagent profile name for the reviewer agent

CARD_TIMEOUT_MS=1800000 # herdr-side timeout (ms)

# --- Worktrees ---
WT_ROOT=$HOME/worktrees

# --- Per-project settings ---
# Key format: PROJ_<key>_repo / _base_ref / _test / _hard / _soft
# <key> = the card's "project" field value with non-alphanumerics replaced
# by _ (my-app -> my_app; shell variable names).
# _hard / _soft are space-separated glob patterns (case syntax).
#
# Example:
# PROJ_my_app_repo="$HOME/my-app"
# PROJ_my_app_base_ref="main"
# PROJ_my_app_test="npm test"
# PROJ_my_app_hard=".env* *.pem keys/* secrets/*"
# PROJ_my_app_soft="Dockerfile docker-compose.yml package.json package-lock.json"
EOF

if [ ! -f "$CONFIG" ]; then
  cp "$SNIPPET_FILE" "$CONFIG"
  chmod 600 "$CONFIG"
fi
cat "$SNIPPET_FILE"

mkdir -p "$WT_ROOT" 2>/dev/null || true

# --- Install agent profiles (runagent mode) ------------------------------------
# setup-agents.sh creates ~/.pi/agent/agents/impl.md and review.md from the
# skill's profiles/ directory. It is idempotent (never overwrites existing files).
if [ -x "$SCRIPT_DIR/setup-agents.sh" ]; then
  log "running setup-agents.sh (install agent profiles)..."
  "$SCRIPT_DIR/setup-agents.sh" || log "WARN: setup-agents.sh failed (profiles may already be installed)"
fi

log "done."
log "Next steps:"
log "  1. Fill MODEL (or MODEL_IMPL / MODEL_REVIEW, optional THINKING_* levels) and add at least one PROJ_<name>_repo block in: $CONFIG"
log "  2. Verify: dispatch.sh status"
