#!/usr/bin/env bash
#
# new-card.sh — create a ticket on the dispatch board and provision it
# (adopt the Dispatch field group, set the project field).
#
# Usage:
#   new-card.sh --title "Add /foo endpoint" --project ai-proxy-king \
#               --desc /path/to/description.md [--list inbox|ready]
#
# The description should follow the card format contract (see
# references/card-format.md).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG=${PLANKA_DISPATCH_CONFIG:-"$HOME/.config/planka-dispatch/config.env"}
[ -f "$CONFIG" ] || { echo "ERROR: config not found: $CONFIG" >&2; exit 2; }
# shellcheck disable=SC1090
source "$CONFIG"

TITLE="" PROJECT="" DESC="" LIST=ready
while [ $# -gt 0 ]; do
  case "$1" in
    --title)   TITLE=$2; shift 2;;
    --project) PROJECT=$2; shift 2;;
    --desc)    DESC=$2; shift 2;;
    --list)    LIST=$2; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$TITLE" ]   || { echo "--title required" >&2; exit 2; }
[ -n "$PROJECT" ] || { echo "--project required (must match a PROJ_<name>_repo key in config)" >&2; exit 2; }
[ -n "$DESC" ]    || { echo "--desc required (markdown file)" >&2; exit 2; }
[ -f "$DESC" ]    || { echo "desc file not found: $DESC" >&2; exit 2; }
REPO_KEY="PROJ_$(echo "${PROJECT//[^a-zA-Z0-9]/_}")_repo"
REPO=${!REPO_KEY:-}
[ -n "$REPO" ]    || { echo "unknown project '$PROJECT' (no ${REPO_KEY} in config)" >&2; exit 2; }

LIST_ID=""
case "$LIST" in
  inbox) LIST_ID=$LIST_INBOX;;
  ready) LIST_ID=$LIST_READY;;
  *) echo "--list must be 'inbox' or 'ready'" >&2; exit 2;;
esac

DESC_TEXT=$(cat "$DESC")
CARD_ID=$(plnk card create --list "$LIST_ID" --title "$TITLE" --description "$DESC_TEXT" --output json | jq -r '.data.id')
plnk field-group create --card "$CARD_ID" --base "$BASE_GROUP" --output json >/dev/null
plnk card field set "$CARD_ID" --group "$FIELD_GROUP" --field "project" --value "$PROJECT" --output json >/dev/null

echo "card created: $CARD_ID"
echo "  title:    $TITLE"
echo "  project:  $PROJECT ($REPO)"
echo "  list:     $LIST"
echo "  next:     flesh out the ticket, then move it to Ready when you want it worked"
