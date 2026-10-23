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

# ── Durable verdict contract: .dispatcher/STATUS.md + .dispatcher/REVIEW.md ──

devflow_fake_config() { # <dir> -> path to a dummy config good enough to source dispatch.sh
    cat > "$1/config.env" <<'EOF'
PLANKA_PROJECT=testproj
PLANKA_BOARD=board1
LIST_INBOX=L_inbox
LIST_READY=L_ready
LIST_CLAIMED=L_claimed
LIST_IN_PROGRESS=L_inprog
LIST_READY_REVIEW=L_ready_review
LIST_AI_REVIEW=L_ai_review
LIST_HUMAN_REVIEW=L_human_review
LIST_DONE=L_done
LIST_REJECTED=L_rejected
FIELD_GROUP=grp
BASE_GROUP=grp
FIELD_PROJECT=f_proj
FIELD_ATTEMPTS=f_attempts
MODEL=test/model
RUNNER=runagent
RUNAGENT=/bin/true
WT_ROOT=/tmp/devflow_verdict_wt
EOF
    echo "$1/config.env"
}

dispatch_probe() { # <config> <snippet> — source dispatch.sh, then eval snippet (no run started)
    (
        set +e
        export PLANKA_DEVFLOW_CONFIG="$1"
        # shellcheck disable=SC1090
        source "$SKILL_DIR/scripts/dispatch.sh" 2>/dev/null
        eval "$2"
    ) 2>/dev/null
}

test_verdict_file_parsing() {
    local TMPD cfg out
    TMPD=$(mktemp -d)
    cfg=$(devflow_fake_config "$TMPD")
    mkdir -p "$TMPD/wt/.dispatcher"
    printf 'STATUS: DONE\n\nWhat changed: everything.\n' > "$TMPD/wt/.dispatcher/STATUS.md"

    out=$(dispatch_probe "$cfg" "verdict_file_text '$TMPD/wt/.dispatcher/STATUS.md'")
    assert_contains "verdict_file_text returns the report body" "$out" "What changed: everything."
    out=$(dispatch_probe "$cfg" "verdict_file_text '$TMPD/wt/.dispatcher/STATUS.md' && echo OK")
    assert_contains "verdict_file_text exits 0 for an existing file" "$out" "OK"

    out=$(dispatch_probe "$cfg" "verdict_file_text '$TMPD/wt/.dispatcher/MISSING.md'; echo rc=\$?")
    assert_contains "missing verdict file exits non-zero (graceful absence)" "$out" "rc=1"

    assert_eq "status_verdict_of parses STATUS: DONE" \
        "$(dispatch_probe "$cfg" "status_verdict_of 'STATUS: DONE'")" "DONE"
    assert_eq "status_verdict_of parses STATUS: FAILED" \
        "$(dispatch_probe "$cfg" "status_verdict_of 'STATUS: FAILED — gate broke'")" "FAILED"
    assert_eq "status_verdict_of is empty for a report without a marker" \
        "$(dispatch_probe "$cfg" "status_verdict_of 'I did things, no marker here'")" ""

    assert_eq "review_verdict_of parses VERDICT: APPROVE" \
        "$(dispatch_probe "$cfg" "review_verdict_of 'VERDICT: APPROVE'")" "APPROVE"
    assert_eq "review_verdict_of parses VERDICT: CHANGES REQUESTED" \
        "$(dispatch_probe "$cfg" "review_verdict_of 'VERDICT: CHANGES REQUESTED'")" "CHANGES_REQUESTED"
    assert_eq "review_verdict_of parses VERDICT: CHANGES_REQUESTED" \
        "$(dispatch_probe "$cfg" "review_verdict_of 'VERDICT: CHANGES_REQUESTED — see issues'")" "CHANGES_REQUESTED"
    assert_eq "review_verdict_of is empty when no verdict line" \
        "$(dispatch_probe "$cfg" "review_verdict_of 'nice work, ships' | tr -d '\n'")" ""
    printf 'preamble\n  VERDICT: CHANGES REQUESTED  \nbody\n' > "$TMPD/multi.txt"
    assert_eq "verdict_line_of quotes the raw VERDICT line" \
        "$(dispatch_probe "$cfg" "verdict_line_of \"\$(cat '$TMPD/multi.txt')\"")" "VERDICT: CHANGES REQUESTED"
    rm -rf "$TMPD"
}

test_impl_verdict_decision() {
    local cfg TMPD
    TMPD=$(mktemp -d)
    cfg=$(devflow_fake_config "$TMPD")

    # No verdict file at all == today's position-only behaviour (graceful).
    assert_eq "no STATUS.md + Ready for Review -> proceed" \
        "$(dispatch_probe "$cfg" "impl_outcome \"\$LIST_READY_REVIEW\" ''")" "proceed"
    assert_eq "no STATUS.md + Ready -> failed" \
        "$(dispatch_probe "$cfg" "impl_outcome \"\$LIST_READY\" ''")" "failed"
    assert_eq "no STATUS.md + other list -> unexpected" \
        "$(dispatch_probe "$cfg" "impl_outcome \"\$LIST_CLAIMED\" ''")" "unexpected"

    # Verdict file decides done-vs-failed when the position is ambiguous.
    assert_eq "STATUS.md DONE + card unmoved -> proceed" \
        "$(dispatch_probe "$cfg" "impl_outcome \"\$LIST_IN_PROGRESS\" DONE")" "proceed"
    assert_eq "STATUS.md DONE + card back in Ready -> proceed (file wins)" \
        "$(dispatch_probe "$cfg" "impl_outcome \"\$LIST_READY\" DONE")" "proceed"
    assert_eq "STATUS.md FAILED + Ready for Review -> failed" \
        "$(dispatch_probe "$cfg" "impl_outcome \"\$LIST_READY_REVIEW\" FAILED")" "failed"
    assert_eq "STATUS.md FAILED + card in Ready -> failed" \
        "$(dispatch_probe "$cfg" "impl_outcome \"\$LIST_READY\" FAILED")" "failed"
    assert_eq "unparseable STATUS.md + other list -> unexpected (no crash)" \
        "$(dispatch_probe "$cfg" "impl_outcome \"\$LIST_CLAIMED\" 'GARBAGE'")" "unexpected"
    rm -rf "$TMPD"
}

test_review_verdict_decision() {
    local cfg TMPD
    TMPD=$(mktemp -d)
    cfg=$(devflow_fake_config "$TMPD")

    # Acceptance case: verdict file present -> annotation uses it.
    assert_eq "REVIEW.md APPROVE + Human Review -> approve stamp from file" \
        "$(dispatch_probe "$cfg" "review_outcome \"\$LIST_HUMAN_REVIEW\" APPROVE")" "approve"
    assert_eq "REVIEW.md CHANGES_REQUESTED + Ready -> changes" \
        "$(dispatch_probe "$cfg" "review_outcome \"\$LIST_READY\" CHANGES_REQUESTED")" "changes"

    # Acceptance case: no verdict file in Human Review -> warning path, no APPROVE.
    assert_eq "no REVIEW.md + Human Review -> warn_missing (no APPROVE stamp)" \
        "$(dispatch_probe "$cfg" "review_outcome \"\$LIST_HUMAN_REVIEW\" ''")" "warn_missing"
    assert_eq "REVIEW.md says CHANGES but card in Human Review -> warn_mismatch" \
        "$(dispatch_probe "$cfg" "review_outcome \"\$LIST_HUMAN_REVIEW\" CHANGES_REQUESTED")" "warn_mismatch"

    # Safe direction stays as today.
    assert_eq "no REVIEW.md + Ready -> changes (today's behaviour)" \
        "$(dispatch_probe "$cfg" "review_outcome \"\$LIST_READY\" ''")" "changes"
    assert_eq "REVIEW.md APPROVE but card in Ready -> changes_mismatch (never approves)" \
        "$(dispatch_probe "$cfg" "review_outcome \"\$LIST_READY\" APPROVE")" "changes_mismatch"
    assert_eq "unexpected list -> unexpected" \
        "$(dispatch_probe "$cfg" "review_outcome \"\$LIST_AI_REVIEW\" APPROVE")" "unexpected"

    # The warning text the human sees when the verdict file is missing.
    if grep -qF 'card moved to Human Review but verdict file missing — human: check transcript' \
         "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "dispatch.sh warns instead of stamping APPROVE without REVIEW.md" "yes"
    else
        run_test "dispatch.sh warns instead of stamping APPROVE without REVIEW.md" "no"
    fi

    if grep -q 'outcome=\$(review_outcome' "$SKILL_DIR/scripts/dispatch.sh" && \
       grep -q 'sf_verdict=\$(status_verdict_of' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "review_card/finish_implementation read the verdict files before stamping" "yes"
    else
        run_test "review_card/finish_implementation read the verdict files before stamping" "no"
    fi
    rm -rf "$TMPD"
}

test_scope_gate_excludes_verdict_dir() {
    local TMPD cfg out
    TMPD=$(mktemp -d)
    cfg=$(devflow_fake_config "$TMPD")

    # Real repo: an accidental .dispatcher/ commit must not trip gate G3.
    mkdir -p "$TMPD/repo"
    git -C "$TMPD/repo" init -q
    git -C "$TMPD/repo" config user.email t@example.com
    git -C "$TMPD/repo" config user.name test
    mkdir -p "$TMPD/repo/src"
    echo 'v1' > "$TMPD/repo/src/app.txt"
    git -C "$TMPD/repo" add -A && git -C "$TMPD/repo" commit -qm 'init'
    mkdir -p "$TMPD/repo/.dispatcher"
    printf 'STATUS: DONE\n' > "$TMPD/repo/.dispatcher/STATUS.md"
    echo 'v2' > "$TMPD/repo/src/app.txt"
    git -C "$TMPD/repo" add -A && git -C "$TMPD/repo" commit -qm 'ticket work'

    out=$(dispatch_probe "$cfg" "scope_diff_files '$TMPD/repo' 'HEAD~1'")
    assert_contains "G3 file list keeps real changes" "$out" "src/app.txt"
    assert_not_contains "G3 file list excludes .dispatcher/ scratch" "$out" ".dispatcher/"

    rm -rf "$TMPD"
}

test_prompts_verdict_contract() {
    local impl="$SKILL_DIR/scripts/prompts/implementer.txt"
    local rev="$SKILL_DIR/scripts/prompts/reviewer.txt"
    local impl_write impl_move rev_write rev_move

    if grep -qF '.dispatcher/STATUS.md' "$impl"; then
        run_test "implementer.txt requires .dispatcher/STATUS.md" "yes"
    else
        run_test "implementer.txt requires .dispatcher/STATUS.md" "no"
    fi
    if grep -qF 'Never `git add` files under `.dispatcher/`' "$impl"; then
        run_test "implementer.txt forbids git-adding .dispatcher/" "yes"
    else
        run_test "implementer.txt forbids git-adding .dispatcher/" "no"
    fi
    impl_write=$(grep -n -m1 -F '.dispatcher/STATUS.md' "$impl" | cut -d: -f1)
    impl_move=$(grep -n -m1 -F 'plnk card move __CARD__ --to-list __LIST_READY_REVIEW__' "$impl" | cut -d: -f1)
    if [ -n "$impl_write" ] && [ -n "$impl_move" ] && [ "$impl_write" -lt "$impl_move" ]; then
        run_test "implementer.txt orders write-STATUS.md BEFORE card move" "yes"
    else
        run_test "implementer.txt orders write-STATUS.md BEFORE card move" "no"
    fi
    if grep -qF 'There is no "plan mode"' "$impl" && grep -qF 'that belief is wrong' "$impl"; then
        run_test "implementer.txt keeps the anti-plan-mode authority assertion" "yes"
    else
        run_test "implementer.txt keeps the anti-plan-mode authority assertion" "no"
    fi
    if grep -qF '__CARD__' "$impl" && grep -qF '__LIST_READY_REVIEW__' "$impl"; then
        run_test "implementer.txt placeholders intact" "yes"
    else
        run_test "implementer.txt placeholders intact" "no"
    fi

    if grep -qF '.dispatcher/REVIEW.md' "$rev"; then
        run_test "reviewer.txt requires .dispatcher/REVIEW.md" "yes"
    else
        run_test "reviewer.txt requires .dispatcher/REVIEW.md" "no"
    fi
    if grep -qF 'never `git add` files under `.dispatcher/`' "$rev"; then
        run_test "reviewer.txt forbids git-adding .dispatcher/" "yes"
    else
        run_test "reviewer.txt forbids git-adding .dispatcher/" "no"
    fi
    rev_write=$(grep -n -m1 -F '.dispatcher/REVIEW.md' "$rev" | cut -d: -f1)
    rev_move=$(grep -n -m1 -F 'plnk card move __CARD__ --to-list __LIST_HUMAN_REVIEW__' "$rev" | cut -d: -f1)
    if [ -n "$rev_write" ] && [ -n "$rev_move" ] && [ "$rev_write" -lt "$rev_move" ]; then
        run_test "reviewer.txt orders write-REVIEW.md BEFORE card move" "yes"
    else
        run_test "reviewer.txt orders write-REVIEW.md BEFORE card move" "no"
    fi
    if grep -qF '__CARD__' "$rev" && grep -qF '__LIST_HUMAN_REVIEW__' "$rev"; then
        run_test "reviewer.txt placeholders intact" "yes"
    else
        run_test "reviewer.txt placeholders intact" "no"
    fi
}

test_cleanup_removes_verdict_dir() {
    if grep -q 'rm -rf -- "$wt/.dispatcher"' "$SKILL_DIR/scripts/dispatch.sh"; then
        run_test "cleanup phase removes leftover .dispatcher/ scratch" "yes"
    else
        run_test "cleanup phase removes leftover .dispatcher/ scratch" "no"
    fi
}

test_verdict_freshness() {
    local cfg TMPD out ra_body ra_clear ra_launch
    TMPD=$(mktemp -d)
    cfg=$(devflow_fake_config "$TMPD")
    mkdir -p "$TMPD/wt/.dispatcher"
    printf 'STATUS: DONE\nstale implementer verdict\n' > "$TMPD/wt/.dispatcher/STATUS.md"
    printf 'VERDICT: APPROVE\nstale reviewer verdict\n' > "$TMPD/wt/.dispatcher/REVIEW.md"

    out=$(dispatch_probe "$cfg" "clear_stale_verdict '$TMPD/wt' review; echo rc=\$?; \
        { [ -f '$TMPD/wt/.dispatcher/REVIEW.md' ] && echo review-kept || echo review-gone; }; \
        { [ -f '$TMPD/wt/.dispatcher/STATUS.md' ] && echo status-kept || echo status-lost; }")
    assert_contains "review launch clears a stale REVIEW.md" "$out" "review-gone"
    assert_contains "review launch leaves STATUS.md alone" "$out" "status-kept"
    assert_contains "clear_stale_verdict exits 0" "$out" "rc=0"

    out=$(dispatch_probe "$cfg" "clear_stale_verdict '$TMPD/wt' impl; echo rc=\$?; \
        { [ -f '$TMPD/wt/.dispatcher/STATUS.md' ] && echo status-kept || echo status-gone; }")
    assert_contains "implementer launch clears a stale STATUS.md" "$out" "status-gone"

    out=$(dispatch_probe "$cfg" "clear_stale_verdict '$TMPD/nonexistent' review; echo rc=\$?")
    assert_contains "no verdict dir at all is graceful (rc=0)" "$out" "rc=0"
    rm -rf "$TMPD"

    # The clear must happen inside run_agent, before the agent is launched.
    ra_body=$(awk '/^run_agent\(\)/,/^}/' "$SKILL_DIR/scripts/dispatch.sh")
    ra_clear=$(printf '%s\n' "$ra_body" | grep -n 'clear_stale_verdict' | head -1 | cut -d: -f1)
    ra_launch=$(printf '%s\n' "$ra_body" | grep -nE '"\$(RUNAGENT|HERDR_RUN)"' | head -1 | cut -d: -f1)
    if [ -n "$ra_clear" ] && [ -n "$ra_launch" ] && [ "$ra_clear" -lt "$ra_launch" ]; then
        run_test "run_agent clears the stale verdict before launching" "yes"
    else
        run_test "run_agent clears the stale verdict before launching" "no"
    fi

    if printf '%s\n' "$ra_body" | grep -q 'clear_stale_verdict "$wt" review' && \
       printf '%s\n' "$ra_body" | grep -q 'clear_stale_verdict "$wt" impl'; then
        run_test "both roles clear their own verdict file" "yes"
    else
        run_test "both roles clear their own verdict file" "no"
    fi

    # Sandboxed reviewer: the worktree is --ro-bind, so .dispatcher must be
    # bound back read-write or the reviewer can never write its verdict.
    if printf '%s\n' "$ra_body" | grep -q -- '--bind $wt/.dispatcher'; then
        run_test "runagent reviewer gets a writable .dispatcher bind" "yes"
    else
        run_test "runagent reviewer gets a writable .dispatcher bind" "no"
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

describe "verdict contract: parsing .dispatcher/STATUS.md and REVIEW.md"
test_verdict_file_parsing

describe "verdict contract: implementation done-vs-failed decision"
test_impl_verdict_decision

describe "verdict contract: review stamp decision (no APPROVE without REVIEW.md)"
test_review_verdict_decision

describe "gate G3: .dispatcher/ scratch excluded from scope check"
test_scope_gate_excludes_verdict_dir

describe "prompts: write verdict file before moving the card"
test_prompts_verdict_contract

describe "cleanup: verdict scratch removed with the worktree"
test_cleanup_removes_verdict_dir

describe "verdict contract: fresh verdict per run (stale files cleared at launch)"
test_verdict_freshness

print_summary
