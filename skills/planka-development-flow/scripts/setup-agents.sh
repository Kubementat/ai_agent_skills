#!/usr/bin/env bash
#
# setup-agents.sh — install runagent profile templates into ~/.pi/agent/agents/.
#
# Installs impl.md and review.md from the skill's profiles/ directory.
# Idempotent: never overwrites an existing profile. Prints installed/skipped
# per profile.
#
# Usage:
#   setup-agents.sh
#
# Profiles are written with a header comment:
#   # installed from planka-development-flow skill — edit freely;
#   # re-running setup will not overwrite.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/profiles"
AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}/agents"

mkdir -p "$AGENT_DIR"

for profile in impl review; do
  src="$PROFILES_DIR/${profile}.md"
  dst="$AGENT_DIR/${profile}.md"
  if [ -f "$dst" ]; then
    echo "SKIPPED: $profile.md already exists (not overwriting)" >&2
  else
    {
      echo "# installed from planka-development-flow skill — edit freely;"
      echo "# re-running setup will not overwrite."
      echo ""
      cat "$src"
    } > "$dst"
    echo "INSTALLED: $profile.md -> $dst" >&2
  fi
done
