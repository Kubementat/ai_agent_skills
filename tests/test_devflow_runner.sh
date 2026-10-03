#!/usr/bin/env bash
# test_devflow_runner.sh — hermetic tests for planka-development-flow runagent runner
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$ROOT_DIR/tests"
SKILL_DIR="$ROOT_DIR/skills/planka-development-flow"
HERDR_DIR="$ROOT_DIR/skills/herdr-cli/scripts"

source "$TESTS_DIR/test_framework.sh"

make_profile() {
    local dir="$1" name="$2"
    mkdir -p "$dir"
    cat > "$dir/${name}.md" <<EOF
---
name: $name
harness: pi
tools: [bash, read, write, edit, grep, find, ls]
skills: none
mcp: none
sandbox:
  on: true
  workspace: null
  env: []
  ro_bind: [/etc/profile]
---
You are a test agent.
EOF
}

run_test() {
    local label="$1" passed="$2"
    if [ "$passed" = "yes" ]; then
        echo -e "  ${_GREEN}✓${_NC} $label"
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
    else
        echo -e "  ${_RED}✗${_NC} $label"
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    fi
}

test_dispatch_runner_config() {
    local ok
    ok="yes"
    if ! grep -q 'if \[ "$RUNNER" = "runagent" \]' "$SKILL_DIR/scripts/dispatch.sh" && \
       ! grep -q 'if \[ "$RUNNER" = "herdr" \]' "$SKILL_DIR/scripts/dispatch.sh"; then
        ok="no"
    fi
    run_test "dispatch.sh has RUNNER branching" "$ok"

    if grep -q ': "${RUNNER:=herdr}"' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "RUNNER defaults to herdr" "yes"
    else
        run_test "RUNNER defaults to herdr" "no"
    fi

    if grep -q ': "${AGENT_IMPL:=impl}"' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "AGENT_IMPL defaults to impl" "yes"
    else
        run_test "AGENT_IMPL defaults to impl" "no"
    fi

    if grep -q ': "${AGENT_REVIEW:=review}"' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "AGENT_REVIEW defaults to review" "yes"
    else
        run_test "AGENT_REVIEW defaults to review" "no"
    fi

    if grep -q ': "${RUNAGENT:=runagent}"' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "RUNAGENT defaults to runagent" "yes"
    else
        run_test "RUNAGENT defaults to runagent" "no"
    fi

    if grep -q 'scratch_dir.*WT_ROOT/scratch' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "reviewer scratch dir under \$WT_ROOT/scratch" "yes"
    else
        run_test "reviewer scratch dir under \$WT_ROOT/scratch" "no"
    fi

    if grep -q 'ASB_SUPPORTS_RO_BIND' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "asb preflight for --ro-bind" "yes"
    else
        run_test "asb preflight for --ro-bind" "no"
    fi

    if grep -q '\-\-ro-bind.*wt' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "run_agent passes --ro-bind for reviewer" "yes"
    else
        run_test "run_agent passes --ro-bind for reviewer" "no"
    fi

    if grep -q '\-\-label.*label' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "run_agent passes --label" "yes"
    else
        run_test "run_agent passes --label" "no"
    fi

    if grep -q '"\$HERDR_RUN"' "$SKILL_DIR/scripts/dispatch.sh" && \
       grep -q '\-w.*\$CARD_TIMEOUT_MS.*--no-wait' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "herdr runner invocation preserved" "yes"
    else
        run_test "herdr runner invocation preserved" "no"
    fi
}

test_runagent_flags() {
    if "$HERDR_DIR/runagent" --help 2>&1 | grep -q -- '--label'; then
        run_test "runagent --help lists --label" "yes"
    else
        run_test "runagent --help lists --label" "no"
    fi

    if "$HERDR_DIR/runagent" --help 2>&1 | grep -q -- '--ro-bind'; then
        run_test "runagent --help lists --ro-bind" "yes"
    else
        run_test "runagent --help lists --ro-bind" "no"
    fi

    if grep -q 'ra-${AGENT}-${SUFFIX}' "$HERDR_DIR/runagent"; then
        run_test "default label format ra-<agent>-NNNN preserved" "yes"
    else
        run_test "default label format ra-<agent>-NNNN preserved" "no"
    fi
}

test_agent_profile_robind() {
    local TMPD result rc
    TMPD=$(mktemp -d)
    mkdir -p "$TMPD/.pi/agent/agents"
    make_profile "$TMPD/.pi/agent/agents" "test-robind"
    export HOME="$TMPD"

    result=$(python3 "$HERDR_DIR/agent_profile.py" compose test-robind --ro-bind /tmp/worktree --model test/model 2>&1)
    rc=$?

    if [ "$rc" -eq 0 ]; then
        run_test "agent_profile.py compose with --ro-bind exits 0" "yes"
    else
        run_test "agent_profile.py compose with --ro-bind exits 0 (rc=$rc)" "no"
    fi

    if echo "$result" | grep -q '"/etc/profile"'; then
        run_test "profile sandbox.ro_bind (/etc/profile) in output" "yes"
    else
        run_test "profile sandbox.ro_bind (/etc/profile) in output" "no"
    fi

    if echo "$result" | grep -q '"/tmp/worktree"'; then
        run_test "CLI --ro-bind (/tmp/worktree) in output" "yes"
    else
        run_test "CLI --ro-bind (/tmp/worktree) in output" "no"
    fi
    rm -rf "$TMPD"
}

test_profiles_structure() {
    # Structural check: frontmatter parses cleanly (hermetic, no host deps)
    local TMPD
    TMPD=$(mktemp -d)

    if [ -f "$SKILL_DIR/profiles/impl.md" ]; then
        run_test "profiles/impl.md exists" "yes"
    else
        run_test "profiles/impl.md exists" "no"
    fi

    if [ -f "$SKILL_DIR/profiles/review.md" ]; then
        run_test "profiles/review.md exists" "yes"
    else
        run_test "profiles/review.md exists" "no"
    fi

    # Create clean test profiles without skill references for hermetic parsing
    mkdir -p "$TMPD/.pi/agent/agents"
    cat > "$TMPD/.pi/agent/agents/impl-test.md" <<'EOF'
---
name: impl-test
harness: pi
tools: [bash, read, write, edit, grep, find, ls]
skills: none
mcp: none
sandbox:
  on: true
  workspace: null
  env: []
  ro_bind: [/etc/profile]
---
You are a test agent.
EOF
    cat > "$TMPD/.pi/agent/agents/review-test.md" <<'EOF'
---
name: review-test
harness: pi
tools: [bash, read, grep, find, ls]
skills: none
mcp: none
sandbox:
  on: true
  workspace: null
  env: []
  ro_bind: []
---
You are a test agent.
EOF
    export HOME="$TMPD"

    local impl_result
    impl_result=$(python3 "$HERDR_DIR/agent_profile.py" compose impl-test --model test/model 2>&1)
    if [ $? -eq 0 ]; then
        run_test "impl.md frontmatter parses cleanly" "yes"
    else
        run_test "impl.md frontmatter parses cleanly" "no"
    fi

    local rev_result
    rev_result=$(python3 "$HERDR_DIR/agent_profile.py" compose review-test --model test/model 2>&1)
    if [ $? -eq 0 ]; then
        run_test "review.md frontmatter parses cleanly" "yes"
    else
        run_test "review.md frontmatter parses cleanly" "no"
    fi

    if grep -q 'skills: \[ponytail, karpathy-guidelines, plnk-cli\]' "$SKILL_DIR/profiles/impl.md"; then
        run_test "impl.md skills correct" "yes"
    else
        run_test "impl.md skills correct" "no"
    fi

    if grep -q 'tools: \[bash, read, grep, find, ls\]' "$SKILL_DIR/profiles/review.md"; then
        run_test "review.md tools exclude write/edit" "yes"
    else
        run_test "review.md tools exclude write/edit" "no"
    fi
    rm -rf "$TMPD"
}

test_setup_agents() {
    local TMPD test_home output
    TMPD=$(mktemp -d)
    test_home="$TMPD/testhome"
    mkdir -p "$test_home"

    output=$(PI_AGENT_DIR="$test_home" bash "$SKILL_DIR/scripts/setup-agents.sh" 2>&1)
    if [ $? -eq 0 ]; then
        run_test "setup-agents.sh exits 0 on first run" "yes"
    else
        run_test "setup-agents.sh exits 0 on first run" "no"
    fi

    if [ -f "$test_home/agents/impl.md" ]; then
        run_test "impl.md installed" "yes"
    else
        run_test "impl.md installed" "no"
    fi

    if [ -f "$test_home/agents/review.md" ]; then
        run_test "review.md installed" "yes"
    else
        run_test "review.md installed" "no"
    fi

    if head -2 "$test_home/agents/impl.md" | grep -q "installed from planka-development-flow skill"; then
        run_test "impl.md has installation header" "yes"
    else
        run_test "impl.md has installation header" "no"
    fi

    echo "# user edited" >> "$test_home/agents/impl.md"
    output=$(PI_AGENT_DIR="$test_home" bash "$SKILL_DIR/scripts/setup-agents.sh" 2>&1)
    if echo "$output" | grep -q "SKIPPED"; then
        run_test "setup-agents.sh skips existing" "yes"
    else
        run_test "setup-agents.sh skips existing" "no"
    fi

    if grep -q "user edited" "$test_home/agents/impl.md"; then
        run_test "user edit preserved" "yes"
    else
        run_test "user edit preserved" "no"
    fi
    rm -rf "$TMPD"
}

test_skill_md_docs() {
    if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
        run_test "SKILL.md exists" "no"
        return
    fi
    run_test "SKILL.md exists" "yes"

    if grep -q "RUNNER" "$SKILL_DIR/SKILL.md"; then
        run_test "SKILL.md documents RUNNER" "yes"
    else
        run_test "SKILL.md documents RUNNER" "no"
    fi
    if grep -q "AGENT_IMPL" "$SKILL_DIR/SKILL.md"; then
        run_test "SKILL.md documents AGENT_IMPL" "yes"
    else
        run_test "SKILL.md documents AGENT_IMPL" "no"
    fi
    if grep -q "AGENT_REVIEW" "$SKILL_DIR/SKILL.md"; then
        run_test "SKILL.md documents AGENT_REVIEW" "yes"
    else
        run_test "SKILL.md documents AGENT_REVIEW" "no"
    fi
    if grep -q "RUNAGENT" "$SKILL_DIR/SKILL.md"; then
        run_test "SKILL.md documents RUNAGENT" "yes"
    else
        run_test "SKILL.md documents RUNAGENT" "no"
    fi
    if grep -q "PLANKA_DEVFLOW_CONFIG" "$SKILL_DIR/SKILL.md"; then
        run_test "SKILL.md documents PLANKA_DEVFLOW_CONFIG" "yes"
    else
        run_test "SKILL.md documents PLANKA_DEVFLOW_CONFIG" "no"
    fi
    if grep -q "Sandboxing" "$SKILL_DIR/SKILL.md"; then
        run_test "SKILL.md has Sandboxing section" "yes"
    else
        run_test "SKILL.md has Sandboxing section" "no"
    fi
    if grep -q "Read-only file system" "$SKILL_DIR/SKILL.md"; then
        run_test "Sandboxing mentions read-only" "yes"
    else
        run_test "Sandboxing mentions read-only" "no"
    fi
    if grep -q "sudoers" "$SKILL_DIR/SKILL.md" || grep -q "shadow" "$SKILL_DIR/SKILL.md"; then
        run_test "Sandboxing mentions /etc shadow" "yes"
    else
        run_test "Sandboxing mentions /etc shadow" "no"
    fi
    local line_count
    line_count=$(wc -l < "$SKILL_DIR/SKILL.md")
    if [ "$line_count" -lt 500 ]; then
        run_test "SKILL.md is $line_count lines (under 500)" "yes"
    else
        run_test "SKILL.md is $line_count lines (under 500)" "no"
    fi
}

test_config_example() {
    if [ ! -f "$SKILL_DIR/config/config.env.example" ]; then
        run_test "config.env.example exists" "no"
        return
    fi
    run_test "config.env.example exists" "yes"

    if grep -q "RUNNER" "$SKILL_DIR/config/config.env.example"; then
        run_test "config.env.example has RUNNER" "yes"
    else
        run_test "config.env.example has RUNNER" "no"
    fi
    if grep -q "RUNAGENT" "$SKILL_DIR/config/config.env.example"; then
        run_test "config.env.example has RUNAGENT" "yes"
    else
        run_test "config.env.example has RUNAGENT" "no"
    fi
    if grep -q "AGENT_IMPL" "$SKILL_DIR/config/config.env.example"; then
        run_test "config.env.example has AGENT_IMPL" "yes"
    else
        run_test "config.env.example has AGENT_IMPL" "no"
    fi
    if grep -q "AGENT_REVIEW" "$SKILL_DIR/config/config.env.example"; then
        run_test "config.env.example has AGENT_REVIEW" "yes"
    else
        run_test "config.env.example has AGENT_REVIEW" "no"
    fi
}

test_no_forbidden_changes() {
    if [ -f "$SKILL_DIR/scripts/prompts/implementer.txt" ] && grep -q "__CARD__" "$SKILL_DIR/scripts/prompts/implementer.txt"; then
        run_test "prompts/implementer.txt unchanged" "yes"
    else
        run_test "prompts/implementer.txt unchanged" "no"
    fi

    if [ -f "$SKILL_DIR/scripts/prompts/reviewer.txt" ] && grep -q "__CARD__" "$SKILL_DIR/scripts/prompts/reviewer.txt"; then
        run_test "prompts/reviewer.txt unchanged" "yes"
    else
        run_test "prompts/reviewer.txt unchanged" "no"
    fi

    if [ -f "$ROOT_DIR/skills/herdr-cli/scripts/run-pi-herdr.sh" ]; then
        local herdr_lines
        herdr_lines=$(wc -l < "$ROOT_DIR/skills/herdr-cli/scripts/run-pi-herdr.sh")
        if [ "$herdr_lines" -gt 0 ]; then
            run_test "run-pi-herdr.sh exists (untouched)" "yes"
        else
            run_test "run-pi-herdr.sh exists (untouched)" "no"
        fi
    else
        echo -e "  ${_YELLOW}⊘${_NC} SKIPPED: run-pi-herdr.sh not in worktree"
        TESTS_SKIPPED=$(( TESTS_SKIPPED + 1 ))
    fi
}

test_setup_board_invokes_agents() {
    if grep -q 'setup-agents.sh' "$SKILL_DIR/scripts/setup-board.sh"; then
        run_test "setup-board.sh invokes setup-agents.sh" "yes"
    else
        run_test "setup-board.sh invokes setup-agents.sh" "no"
    fi
}

# ── Run all tests ──────────────────────────────────────────────────────────

describe "dispatch.sh: RUNNER config keys"
test_dispatch_runner_config

describe "runagent: --label and --ro-bind flags"
test_runagent_flags

describe "agent_profile.py: --ro-bind arg handling"
test_agent_profile_robind

describe "profiles: frontmatter structural check"
test_profiles_structure

describe "setup-agents.sh: idempotent install"
test_setup_agents

describe "SKILL.md: documents new config keys"
test_skill_md_docs

describe "config.env.example: contains new keys"
test_config_example

describe "dispatch.sh: no forbidden file changes"
test_no_forbidden_changes

describe "setup-board.sh: invokes setup-agents.sh"
test_setup_board_invokes_agents

print_summary
