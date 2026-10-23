#!/usr/bin/env bash
# test_devflow_launch.sh — hermetic tests for the hardened dispatcher launch
# path (planka-development-flow): sed-free prompt rendering, launcher logs,
# fail-closed launch verification and the pi-session capture fallback.
#
# No board, no credentials, no herdr: everything runs against temp HOMEs and
# grep-level source assertions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/planka-development-flow"
DISPATCH="$SKILL_DIR/scripts/dispatch.sh"

source "$SCRIPT_DIR/test_framework.sh"

# Source without full-line comments — assertions must look at code, not prose.
code_only() { grep -v '^[[:space:]]*#' "$1"; }

cleanup_dirs=()
register_cleanup() { cleanup_dirs+=("$1"); }
trap 'for d in "${cleanup_dirs[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done' EXIT

# ─── syntax ──────────────────────────────────────────────────────────────────
describe "dispatch.sh + skill scripts: bash -n"

_syntax_ok=yes
for s in "$SKILL_DIR"/scripts/*.sh; do
    if ! bash -n "$s" 2>/dev/null; then
        _syntax_ok=no
        echo "    syntax error in: $s"
    fi
done
assert_eq "bash -n passes on every skill script" "$_syntax_ok" "yes"

# ─── prompt rendering: no sed left ───────────────────────────────────────────
describe "prompt rendering: pure bash substitution"

_code=$(code_only "$DISPATCH")
if echo "$_code" | grep -qE '(^|[;&|[:space:]])sed([[:space:]]|$)'; then
    assert_eq "no sed invocation remains in dispatch.sh" "found" "none"
else
    assert_eq "no sed invocation remains in dispatch.sh" "none" "none"
fi
assert_not_contains "no s|__TOKEN__| renderer" "$_code" 's|__'

if grep -q 'content={content//' "$DISPATCH" || grep -qF 'content=${content//' "$DISPATCH"; then
    assert_eq "render_prompt uses bash parameter expansion" "yes" "yes"
else
    assert_eq "render_prompt uses bash parameter expansion" "no" "yes"
fi
if grep -q 'render_prompt' "$DISPATCH" && grep -q 'render_prompt "\$promptfile"' "$DISPATCH"; then
    assert_eq "run_agent renders via render_prompt" "yes" "yes"
else
    assert_eq "run_agent renders via render_prompt" "no" "yes"
fi
if grep -q 'prompt template render failed' "$DISPATCH"; then
    assert_eq "empty-prompt guard preserved" "yes" "yes"
else
    assert_eq "empty-prompt guard preserved" "no" "yes"
fi

# Functional: extract render_prompt() from dispatch.sh and feed it values that
# used to break the sed renderer (slashes) and bash 5.3 replacement metachars.
_extract_fn() { # <file> <function-name> — prints the top-level function body
    awk -v fn="$2" '
        $0 ~ "^"fn"\\(\\)" {infn=1}
        infn {print}
        infn && /^}/ {exit}
    ' "$1"
}
describe "render_prompt: values with slashes and metacharacters"

RT=$(mktemp -d); register_cleanup "$RT"
{
    _extract_fn "$DISPATCH" render_prompt
    cat <<'EOF'
set -uo pipefail
printf 'card __CARD__ base __BASE_REF__ r __LIST_READY__ rr __LIST_READY_REVIEW__ hr __LIST_HUMAN_REVIEW__\n' > "$RT/tpl.txt"
render_prompt "$RT/tpl.txt" CARD 42 BASE_REF "origin/feat/pyinfra-migration" \
    LIST_READY "123/456" LIST_READY_REVIEW "a|b&c" LIST_HUMAN_REVIEW 'x\y $z'
EOF
} > "$RT/render.sh"
rendered=$(RT="$RT" bash "$RT/render.sh" 2>/dev/null)
assert_contains "slash-bearing base_ref survives" "$rendered" "origin/feat/pyinfra-migration"
assert_contains "placeholder substituted"         "$rendered" "card 42"
assert_not_contains "no leftover placeholder"     "$rendered" "__BASE_REF__"
assert_contains "ampersand in value stays literal" "$rendered" "a|b&c"
assert_contains "backslash/dollar stay literal"    "$rendered" 'x\y $z'

# ─── launcher logs (no /dev/null) ────────────────────────────────────────────
describe "launch output goes to a per-launch log"

if grep -q 'LAUNCH_LOG_DIR:=$HOME/.config/planka-development-flow/launch-logs' "$DISPATCH"; then
    assert_eq "launch log dir defaults under the skill config dir" "yes" "yes"
else
    assert_eq "launch log dir defaults under the skill config dir" "no" "yes"
fi
if grep -q 'launch-%s.log' "$DISPATCH" && grep -q 'mkdir -p "$LAUNCH_LOG_DIR"' "$DISPATCH"; then
    assert_eq "per-label log file launch-<label>.log created" "yes" "yes"
else
    assert_eq "per-label log file launch-<label>.log created" "no" "yes"
fi

# The HERDR_RUN / RUNAGENT invocations terminate in a `--no-wait` line; that
# line carries their redirection and must append to $logpath, not /dev/null.
_launcher_lines=$(grep -- '--no-wait' "$DISPATCH")
if echo "$_launcher_lines" | grep -q 'logpath'; then
    assert_eq "launcher output redirected to the launch log" "yes" "yes"
else
    assert_eq "launcher output redirected to the launch log" "no" "yes"
fi
if echo "$_launcher_lines" | grep -q '/dev/null'; then
    assert_eq "launcher output no longer sent to /dev/null" "dev-null" "clean"
else
    assert_eq "launcher output no longer sent to /dev/null" "clean" "clean"
fi

# ─── fail-closed launch verification ─────────────────────────────────────────
describe "fail-closed launch verification"

if grep -q 'wait_for_workspace()' "$DISPATCH"; then
    assert_eq "wait_for_workspace helper exists" "yes" "yes"
else
    assert_eq "wait_for_workspace helper exists" "no" "yes"
fi
if grep -q 'if ! wait_for_workspace "\$label"' "$DISPATCH"; then
    assert_eq "run_agent verifies the workspace appeared" "yes" "yes"
else
    assert_eq "run_agent verifies the workspace appeared" "no" "yes"
fi
if grep -q 'launch failed: no herdr workspace for \$label' "$DISPATCH"; then
    assert_eq "launch failure is reported on the card with the log path" "yes" "yes"
else
    assert_eq "launch failure is reported on the card with the log path" "no" "yes"
fi
# The "launched N" line must describe the verified set, not the intent.
if grep -q 'launched ${#launched\[@\]}' "$DISPATCH"; then
    assert_eq "launch log line reports the verified set" "yes" "yes"
else
    assert_eq "launch log line reports the verified set" "no" "yes"
fi
if grep -q 'run_agent "\$c" "impl-\$c"' "$DISPATCH"; then
    assert_eq "implementer launches still run in parallel" "yes" "yes"
else
    assert_eq "implementer launches still run in parallel" "no" "yes"
fi

# Functional: extract wait_for_workspace()/ws_id_by_label() and drive them
# with a stub herdr, so fail-closed verification is proven, not asserted.
describe "wait_for_workspace: fail-closed polling against a stub herdr"

WTM=$(mktemp -d); register_cleanup "$WTM"
mkdir -p "$WTM/bin"
cat > "$WTM/bin/herdr" <<'EOS'
#!/usr/bin/env bash
# stub: `herdr workspace list` — the impl-9 workspace appears on the 3rd call
n=$(($(cat "$CNT_FILE") + 1)); printf '%s' "$n" > "$CNT_FILE"
if [ "$n" -ge 3 ] && [ "${SHOW_WS:-yes}" = yes ]; then
  printf '{"result":{"workspaces":[{"number":1,"workspace_id":"w1","label":"impl-9"}]}}\n'
else
  printf '{"result":{"workspaces":[]}}\n'
fi
EOS
chmod +x "$WTM/bin/herdr"
printf '0' > "$WTM/calls"
{
    _extract_fn "$DISPATCH" ws_id_by_label
    _extract_fn "$DISPATCH" wait_for_workspace
    cat <<'EOF'
set -uo pipefail
export CNT_FILE
LAUNCH_VERIFY_INTERVAL=1
LAUNCH_VERIFY_TIMEOUT=${TIMEOUT:-5}
t_start=$(date +%s)
wait_for_workspace impl-9; rc=$?
echo "rc=$rc elapsed=$(( $(date +%s) - t_start ))"
EOF
} > "$WTM/wait.sh"
res=$(PATH="$WTM/bin:$PATH" CNT_FILE="$WTM/calls" bash "$WTM/wait.sh")
assert_contains "waits until the workspace appears, then succeeds" "$res" "rc=0"

printf '0' > "$WTM/calls"
res=$(PATH="$WTM/bin:$PATH" CNT_FILE="$WTM/calls" SHOW_WS=no TIMEOUT=2 bash "$WTM/wait.sh")
assert_contains "a workspace that never appears fails the launch" "$res" "rc=1"

# ─── capture_report session-dir fallback ─────────────────────────────────────
describe "pi_session_dir encoding (--<dashed-path>--)"

ST=$(mktemp -d); register_cleanup "$ST"
FAKE_HOME="$ST/home"
WT="$ST/wt/1889157694812587407"
mkdir -p "$FAKE_HOME" "$WT"
# Expected dir computed independently of the implementation: pi replaces every
# slash with a dash (so the leading slash adds one dash) and wraps the result
# in one more dash on each side.
EXPECTED_NAME="-$(printf '%s' "$WT" | tr '/' '-')--"
mkdir -p "$FAKE_HOME/.pi/agent/sessions/$EXPECTED_NAME"
cat > "$FAKE_HOME/.pi/agent/sessions/$EXPECTED_NAME/2026-01-01T00-00-00-000Z_a.jsonl" <<'EOF'
{"type":"session","id":"x"}
{"type":"message","message":{"role":"user","content":[{"type":"text","text":"do the thing"}]}}
{"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","name":"bash"}]}}
{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"STATUS: DONE — marker report text"}]}}
{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":""}]}}
EOF

out=$(HOME="$FAKE_HOME" PLANKA_DEVFLOW_CONFIG="$ST/no-config.env" \
      bash "$DISPATCH" test-capture "$WT" 2>"$ST/err")
rc=$?
assert_eq "test-capture extracts from the correct session dir (exit code)" "$rc" "0"
assert_contains "test-capture prints the last assistant text" "$out" "STATUS: DONE — marker report text"
if grep -q '^# session: ' "$ST/err"; then
    assert_eq "test-capture names the session file on stderr" "yes" "yes"
else
    assert_eq "test-capture names the session file on stderr" "no" "yes"
fi
# The old (single-leading-dash) derivation must not be accepted.
if [ ! -d "$FAKE_HOME/.pi/agent/sessions/-$(printf '%s' "${WT#/}" | tr '/' '-')" ]; then
    assert_eq "no single-dash session dir is created/read" "yes" "yes"
else
    assert_eq "no single-dash session dir is created/read" "no" "yes"
fi

describe "test-capture failure modes"

MISS=$(mktemp -d); register_cleanup "$MISS"
out=$(HOME="$FAKE_HOME" bash "$DISPATCH" test-capture "$MISS/nowhere" 2>&1)
rc=$?
assert_eq "test-capture fails when there is no session dir" "$rc" "1"
assert_contains "failure names the derived dir" "$out" "-$(printf '%s' "$MISS/nowhere" | tr '/' '-')--"

out=$(HOME="$FAKE_HOME" bash "$DISPATCH" test-capture 2>&1)
rc=$?
assert_eq "test-capture without a worktree exits 2" "$rc" "2"

# newest-session selection: touch an older-named file last
mkdir -p "$FAKE_HOME/.pi/agent/sessions/$EXPECTED_NAME"
sleep 1
printf '%s\n' '{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"NEWEST report"}]}}' \
    > "$FAKE_HOME/.pi/agent/sessions/$EXPECTED_NAME/2025-12-31T00-00-00-000Z_b.jsonl"
touch "$FAKE_HOME/.pi/agent/sessions/$EXPECTED_NAME/2025-12-31T00-00-00-000Z_b.jsonl"
out=$(HOME="$FAKE_HOME" bash "$DISPATCH" test-capture "$WT" 2>/dev/null)
assert_contains "test-capture picks the newest session file" "$out" "NEWEST report"

# ─── docs ────────────────────────────────────────────────────────────────────
describe "docs / config mention the new knobs"

for f in "$SKILL_DIR/SKILL.md" "$SKILL_DIR/README.md" "$SKILL_DIR/config/config.env.example"; do
    if grep -q 'test-capture' "$f"; then
        assert_eq "$(basename "$f") documents test-capture" "yes" "yes"
    else
        assert_eq "$(basename "$f") documents test-capture" "no" "yes"
    fi
    if grep -q 'LAUNCH_LOG_DIR' "$f"; then
        assert_eq "$(basename "$f") documents LAUNCH_LOG_DIR" "yes" "yes"
    else
        assert_eq "$(basename "$f") documents LAUNCH_LOG_DIR" "no" "yes"
    fi
done

print_summary
