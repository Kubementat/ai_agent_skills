#!/usr/bin/env bash
# Tests for install-agent.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/install-agent.sh"
source "$REPO_ROOT/tests/test_framework.sh"

# ─── fixtures ────────────────────────────────────────────────────────────────
# Pick two real agents from agents/pi/
# *.chain.md are legacy chain definitions; install-agent.sh skips them by design.
mapfile -t _ALL_AGENTS < <(find "$REPO_ROOT/agents/pi" -maxdepth 1 -name "*.md" ! -name "*.chain.md" | xargs -I{} basename {} .md | sort)
AGENT_A="${_ALL_AGENTS[0]}"
AGENT_B="${_ALL_AGENTS[1]}"

# ─── helpers ─────────────────────────────────────────────────────────────────
run() { run_script "$SCRIPT" "$@"; }

cleanup_dirs=()
register_cleanup() { cleanup_dirs+=("$1"); }
cleanup_all() {
    for d in "${cleanup_dirs[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done
}
trap cleanup_all EXIT

# ─── 1. Help / usage ─────────────────────────────────────────────────────────
describe "install-agent.sh --help"

run --help
assert_exit_code "exits 0"                   "$_RC" "0"
assert_contains  "shows Usage"               "$_OUT" "Usage:"
assert_contains  "documents --all"           "$_OUT" "--all"
assert_contains  "documents --target-dir"    "$_OUT" "--target-dir"
assert_contains  "documents --interactive"   "$_OUT" "--interactive"

# ─── 2. --list ───────────────────────────────────────────────────────────────
describe "install-agent.sh --list"

run --list
assert_exit_code "exits 0"           "$_RC" "0"
assert_contains  "header present"    "$_OUT" "Available Pi Agents"
assert_contains  "lists $AGENT_A"    "$_OUT" "$AGENT_A"
assert_contains  "shows total count" "$_OUT" "Total agents available"

# ─── 3. No action specified fails ────────────────────────────────────────────
describe "install-agent.sh: no action"

run
assert_exit_code "exits non-zero"          "$_RC" "1"
assert_contains  "error mentions --all"    "$_OUT" "--all"

# ─── 4. Unknown agent fails ──────────────────────────────────────────────────
describe "install-agent.sh: unknown agent name"

TMP=$(mktemp -d); register_cleanup "$TMP"
run --target-dir "$TMP" notanagent
assert_exit_code "exits non-zero"              "$_RC" "1"
assert_contains  "error mentions not found"    "$_OUT" "not found"

# ─── 5. --target-dir must exist ──────────────────────────────────────────────
describe "install-agent.sh: --target-dir non-existent path"

run --target-dir /no/such/path "$AGENT_A"
assert_exit_code "exits non-zero"           "$_RC" "1"
assert_contains  "error mentions directory" "$_OUT" "does not exist"

# ─── 6. Default install base is $HOME/.pi/agent/agents ───────────────────────
describe "install-agent.sh: default target resolves to \$HOME"

# Use --list which calls list_agents and prints INSTALL_BASE
run --list
assert_contains "installation target mentions HOME" "$_OUT" "$HOME/.pi/agent/agents"

# ─── 7. Symlink install into --target-dir ────────────────────────────────────
describe "install-agent.sh: symlink install into --target-dir"

TMP=$(mktemp -d); register_cleanup "$TMP"
run --target-dir "$TMP" "$AGENT_A" --force
assert_exit_code "exits 0"                          "$_RC" "0"
assert_dir_exists "install dir created"             "$TMP/.pi/agent/agents"
assert_symlink    "$AGENT_A is a symlink"            "$TMP/.pi/agent/agents/$AGENT_A.md"
assert_symlink_target "symlink points to repo source" \
    "$TMP/.pi/agent/agents/$AGENT_A.md" \
    "$REPO_ROOT/agents/pi/$AGENT_A.md"

# ─── 8. Multiple agents in one invocation ────────────────────────────────────
describe "install-agent.sh: multiple agents"

TMP=$(mktemp -d); register_cleanup "$TMP"
run --target-dir "$TMP" "$AGENT_A" "$AGENT_B" --force
assert_exit_code "exits 0"         "$_RC" "0"
assert_symlink   "$AGENT_A installed" "$TMP/.pi/agent/agents/$AGENT_A.md"
assert_symlink   "$AGENT_B installed" "$TMP/.pi/agent/agents/$AGENT_B.md"

# ─── 9. --all installs every agent ───────────────────────────────────────────
describe "install-agent.sh: --all installs all agents"

TMP=$(mktemp -d); register_cleanup "$TMP"
run --target-dir "$TMP" --all --force
assert_exit_code "exits 0" "$_RC" "0"

for agent_name in "${_ALL_AGENTS[@]}"; do
    assert_symlink "agent $agent_name installed" "$TMP/.pi/agent/agents/$agent_name.md"
done

# ─── 10. Idempotent re-install ───────────────────────────────────────────────
describe "install-agent.sh: idempotent re-install"

TMP=$(mktemp -d); register_cleanup "$TMP"
run --target-dir "$TMP" "$AGENT_A" --force
run --target-dir "$TMP" "$AGENT_A" --force
assert_exit_code "second install exits 0"    "$_RC" "0"
assert_symlink   "symlink still present"     "$TMP/.pi/agent/agents/$AGENT_A.md"
assert_symlink_target "symlink target unchanged" \
    "$TMP/.pi/agent/agents/$AGENT_A.md" \
    "$REPO_ROOT/agents/pi/$AGENT_A.md"

# ─── 11. Stale symlink is replaced ───────────────────────────────────────────
describe "install-agent.sh: stale symlink replaced"

TMP=$(mktemp -d); register_cleanup "$TMP"
mkdir -p "$TMP/.pi/agent/agents"
# plant a broken symlink pointing nowhere
ln -s /nonexistent/old.md "$TMP/.pi/agent/agents/$AGENT_A.md"

run --target-dir "$TMP" "$AGENT_A" --force
assert_exit_code "exits 0 after stale replace"       "$_RC" "0"
assert_symlink   "link is still a symlink"            "$TMP/.pi/agent/agents/$AGENT_A.md"
assert_symlink_target "link now points to repo" \
    "$TMP/.pi/agent/agents/$AGENT_A.md" \
    "$REPO_ROOT/agents/pi/$AGENT_A.md"

# ─── Summary ─────────────────────────────────────────────────────────────────
print_summary
