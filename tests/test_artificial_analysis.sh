#!/usr/bin/env bash
# Tests for skills/artificial-analysis (aa.py).
#
# Fully OFFLINE: every CLI assertion runs with --fixture-dir and AA_API_KEY unset,
# and the cache test injects a stubbed transport. No network, no API key required.
#
# Usage:  bash tests/test_artificial_analysis.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/artificial-analysis"
AA="$SKILL_DIR/scripts/aa.py"
FIXTURES="$SKILL_DIR/tests/fixtures"
source "$REPO_ROOT/tests/test_framework.sh"

# No key, no live calls — even by accident.
unset AA_API_KEY

command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }
[[ -f "$AA" ]] || { echo "missing $AA"; exit 1; }
[[ -d "$FIXTURES" ]] || { echo "missing fixtures $FIXTURES"; exit 1; }

cleanup_dirs=()
register_cleanup() { cleanup_dirs+=("$1"); }
cleanup_all() {
    for d in "${cleanup_dirs[@]:-}"; do
        [[ -n "$d" ]] && rm -rf "$d"
    done
}
trap cleanup_all EXIT

fresh_tmp() { mktemp -d; }

# fits_of "$OUTPUT" "<model name prefix>" -> yes / no / - / unknown (last column of that row)
fits_of() {
    awk -v name="$2" 'index($0, name) == 1 { print $NF; exit }' <<< "$1"
}

# run_aa [--global flags] subcommand args...   -> sets _OUT / _RC
run_aa() {
    _OUT=$(env -u AA_API_KEY python3 "$AA" "$@" 2>&1)
    _RC=$?
    return 0
}

# ─── 1. help / stdlib purity ──────────────────────────────────────────────────
describe "aa.py --help and stdlib-only imports"

run_aa --help
assert_exit_code "exits 0 with no key and no network" "$_RC" "0"
assert_contains  "shows usage"            "$_OUT" "usage:"
assert_contains  "documents models"       "$_OUT" "models"
assert_contains  "documents compare"      "$_OUT" "compare"
assert_contains  "documents search"       "$_OUT" "search"
assert_contains  "documents open-weights" "$_OUT" "open-weights"
assert_contains  "documents raw"          "$_OUT" "raw"
assert_contains  "documents --fixture-dir" "$_OUT" "--fixture-dir"

STDLIB_OK=$(python3 - "$AA" <<'PY'
import ast, sys
allowed = {"argparse", "difflib", "json", "os", "re", "sys", "time", "urllib",
           "urllib.error", "urllib.parse", "urllib.request", "pathlib", "__future__"}
tree = ast.parse(open(sys.argv[1]).read())
found = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            found.add(alias.name)
    elif isinstance(node, ast.ImportFrom):
        if node.level == 0 and node.module:
            found.add(node.module)
bad = sorted(m for m in found if m.split(".")[0] not in {a.split(".")[0] for a in allowed})
print(",".join(bad))
PY
)
assert_eq "imports only Python 3 stdlib modules" "$STDLIB_OK" ""

# ─── 1b. missing API key (no fixtures, empty HOME, still zero network) ─────────
describe "aa.py without an API key"

EMPTY_HOME=$(fresh_tmp); register_cleanup "$EMPTY_HOME"
_OUT=$(env -u AA_API_KEY HOME="$EMPTY_HOME" python3 "$AA" models 2>&1); _RC=$?
assert_exit_code "missing key exits 1"              "$_RC" "1"
assert_contains  "names AA_API_KEY"                 "$_OUT" "AA_API_KEY"
assert_contains  "names the config file"            "$_OUT" ".config/artificialanalysis/config.env"
assert_not_contains "does not print a key-looking value" "$_OUT" "x-api-key"

_OUT=$(env -u AA_API_KEY HOME="$EMPTY_HOME" python3 "$AA" --fixture-dir "$FIXTURES"/nope models 2>&1); _RC=$?
assert_exit_code "bad --fixture-dir exits 1"        "$_RC" "1"

# ─── 2. models ────────────────────────────────────────────────────────────────
describe "aa.py models (fixtures)"

run_aa --fixture-dir "$FIXTURES" models --limit 10
assert_exit_code "exits 0"                 "$_RC" "0"
assert_contains  "prints column headers"   "$_OUT" "INTEL"
assert_contains  "prints a fixture model"  "$_OUT" "Claude Opus 5.5"
assert_contains  "prints an intel score"   "$_OUT" "57.6"
assert_contains  "prints attribution"      "$_OUT" "Data: artificialanalysis.ai (Intelligence Index v"

run_aa --fixture-dir "$FIXTURES" models --sort price --limit 5 --json
assert_exit_code "--json exits 0"          "$_RC" "0"
assert_contains  "--json emits models key"  "$_OUT" '"models"'
assert_contains  "--json emits capability"  "$_OUT" '"capability_indexes"'

run_aa --fixture-dir "$FIXTURES" models --min-intel 50 --limit 25
assert_not_contains "--min-intel filters weak models" "$_OUT" "Gemma 3 27B Instruct"

run_aa --fixture-dir "$FIXTURES" models --since 2026-06-01 --limit 25
assert_exit_code "--since exits 0"         "$_RC" "0"
assert_contains  "--since keeps a 2026 model" "$_OUT" "2026-09-22"

# ─── 3. compare ───────────────────────────────────────────────────────────────
describe "aa.py compare (fixtures, id-join across both endpoints)"

run_aa --fixture-dir "$FIXTURES" compare gpt-6-astra-xhigh qwen3-5-9b
assert_exit_code "exits 0 for two valid slugs"      "$_RC" "0"
assert_contains  "shows first model"                "$_OUT" "GPT-6 Astra (Xhigh)"
assert_contains  "shows second model"               "$_OUT" "Qwen3.5 9B (Reasoning)"
assert_contains  "shows agentic index (v2 join)"    "$_OUT" "Agentic Index"
assert_contains  "agentic value from v2 endpoint"   "$_OUT" "50.2"
assert_contains  "shows capability index (v2 join)" "$_OUT" "Capability: Finance"
assert_contains  "shows per-benchmark score (legacy join)" "$_OUT" "GPQA"
assert_contains  "gpqa value from legacy endpoint"  "$_OUT" "0.963"
assert_contains  "shows pricing row"                "$_OUT" "\$/1M output"
assert_contains  "shows tokens/s row"               "$_OUT" "Median tokens/s"
assert_contains  "shows release dates"              "$_OUT" "Released"
assert_contains  "prints attribution"               "$_OUT" "Data: artificialanalysis.ai"

run_aa --fixture-dir "$FIXTURES" compare totally-not-a-model
assert_exit_code "bogus slug exits non-zero"  "$_RC" "2"
assert_contains  "names the unknown slug"     "$_OUT" "Unknown model"
assert_contains  "suggests nearest names"     "$_OUT" "Did you mean:"

run_aa --fixture-dir "$FIXTURES" compare gpt-6-astra-xhigh nope-not-a-model
assert_exit_code "one bad slug fails the call" "$_RC" "2"

# ─── 4. search ────────────────────────────────────────────────────────────────
describe "aa.py search (fixtures)"

run_aa --fixture-dir "$FIXTURES" search qwen
assert_exit_code "exits 0"                    "$_RC" "0"
assert_contains  "finds matching model"       "$_OUT" "Qwen3.5 27B (Reasoning)"
assert_contains  "reports match count"        "$_OUT" "models match"

run_aa --fixture-dir "$FIXTURES" search deepseek
assert_exit_code "creator search exits 0"     "$_RC" "0"
assert_contains  "matches on creator"         "$_OUT" "DeepSeek"

run_aa --fixture-dir "$FIXTURES" search zzz-nonsense-zzz
assert_exit_code "no-match still exits 0"     "$_RC" "0"
assert_contains  "reports zero matches"       "$_OUT" "0 models match"

# ─── 5. open-weights ──────────────────────────────────────────────────────────
describe "aa.py open-weights --ram 120 --quant q4_k_m (fixtures)"

run_aa --fixture-dir "$FIXTURES" open-weights --ram 120 --quant q4_k_m
assert_exit_code "exits 0"                          "$_RC" "0"
assert_contains  "prints FITS column"               "$_OUT" "FITS"
assert_contains  "lists open-weights Qwen3.5 122B"  "$_OUT" "Qwen3.5 122B A10B (Reasoning)"
assert_eq        "122B model fits (yes)"            "$(fits_of "$_OUT" "Qwen3.5 122B A10B")" "yes"
assert_contains  "lists gpt-oss-120b as fitting"    "$_OUT" "gpt-oss-120b (High)"
assert_eq        "gpt-oss-120b fits (yes)"          "$(fits_of "$_OUT" "gpt-oss-120b")" "yes"
assert_contains  "lists too-large Qwen3 235B"       "$_OUT" "Qwen3 235B A22B 2507 Instruct"
assert_eq        "235B model does not fit (no)"     "$(fits_of "$_OUT" "Qwen3 235B A22B 2507")" "no"
assert_eq        "397B model does not fit (no)"     "$(fits_of "$_OUT" "Qwen3.5 397B A17B")" "no"
assert_eq        "9B model fits (yes)"              "$(fits_of "$_OUT" "Qwen3.5 9B")" "yes"
assert_not_contains "excludes closed Claude"        "$_OUT" "Claude Opus 5.5"
assert_not_contains "excludes closed GPT"           "$_OUT" "GPT-6 Astra"
assert_not_contains "excludes closed Gemini"        "$_OUT" "Gemini 2.5 Pro"
assert_not_contains "excludes closed Grok"          "$_OUT" "Grok 4.6"
assert_contains  "states it is an estimate"         "$_OUT" "Estimate only"
assert_contains  "mentions KV cache caveat"         "$_OUT" "KV cache"
assert_contains  "counts excluded closed models"    "$_OUT" "closed-weight model(s) excluded"
assert_contains  "prints attribution"               "$_OUT" "Data: artificialanalysis.ai"

run_aa --fixture-dir "$FIXTURES" open-weights --ram 120 --quant fp16
assert_exit_code "fp16 exits 0"                     "$_RC" "0"
assert_eq        "fp16 marks 122B as not fitting"   "$(fits_of "$_OUT" "Qwen3.5 122B A10B")" "no"

run_aa --fixture-dir "$FIXTURES" open-weights --limit 200 --all
assert_exit_code "--all exits 0"                    "$_RC" "0"
assert_contains  "--all includes unknown-param open model" "$_OUT" "Kimi K2.6 (Reasoning)"
assert_contains  "unknown params marked unknown"    "$_OUT" "unknown"

run_aa --fixture-dir "$FIXTURES" open-weights --limit 200
assert_not_contains "without --all unknown-param models are excluded" "$_OUT" "Kimi K2.6 (Reasoning)"

# ─── 6. raw (fixtures) ────────────────────────────────────────────────────────
describe "aa.py raw (fixtures)"

run_aa --fixture-dir "$FIXTURES" raw media/text-to-image/models/free
assert_exit_code "exits 0"                  "$_RC" "0"
assert_contains  "prints elo field"         "$_OUT" "elo"
assert_contains  "prints tier"              "$_OUT" "\"tier\": \"free\""

run_aa --fixture-dir "$FIXTURES" raw media/text-to-video/models/free
assert_exit_code "missing fixture exits non-zero" "$_RC" "2"
assert_contains  "explains offline mode"    "$_OUT" "No fixture"

run_aa --fixture-dir "$FIXTURES" raw ../secrets
assert_exit_code "path traversal refused"   "$_RC" "2"

# --param must reach the fixture lookup (regression: NameError on 'params').
run_aa --fixture-dir "$FIXTURES" raw language/models/free --param page=1
assert_exit_code "--param page=1 exits 0"      "$_RC" "0"
assert_contains  "--param replays page 1"      "$_OUT" "\"page\": 1"

run_aa --fixture-dir "$FIXTURES" raw language/models/free --param page=4
assert_exit_code "--param page=4 exits 0"      "$_RC" "0"
assert_contains  "--param replays last page"   "$_OUT" "\"has_more\": false"

run_aa --fixture-dir "$FIXTURES" raw language/models/free
assert_exit_code "no page param is a clear error" "$_RC" "2"
assert_contains  "error names the missing path"   "$_OUT" "No fixture"

# ─── 7. cache TTL + transport injection ───────────────────────────────────────
describe "aa.py cache TTL (module import with stubbed transport)"

TMP=$(fresh_tmp); register_cleanup "$TMP"
HELPER="$TMP/cache_test.py"
cat > "$HELPER" <<'PY'
"""Import aa.py as a module and exercise the cache with a stubbed transport."""
import importlib.util
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]).parent))
spec = importlib.util.spec_from_file_location("aa", sys.argv[1])
aa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aa)

fixtures = Path(sys.argv[2])
legacy_body = (fixtures / "legacy_models.json").read_text()
page1 = json.loads((fixtures / "v2_free_page1.json").read_text())
last = json.loads((fixtures / "v2_free_page4.json").read_text())

calls = []


def stub_transport(url, headers):
    """Stand-in for aa.default_transport — records calls, never touches the network."""
    calls.append(url)
    if "data/llms/models" in url:
        body = legacy_body
    elif "page=1" in url:
        body = json.dumps(page1)
    else:  # any later page: the recorded last page ends the pagination loop
        body = json.dumps(last)
    return 200, {"X-RateLimit-Remaining": "97", "X-AA-Tier": "free"}, body


def client(cache_dir, ttl=None, refresh=False):
    return aa.Client(cache_dir=cache_dir, ttl=ttl, refresh=refresh,
                     transport=stub_transport, api_key="stub-key-not-secret")


cache = sys.argv[3]
failures = []


def check(label, condition, detail=""):
    print(("PASS " if condition else "FAIL ") + label + (" — " + detail if detail and not condition else ""))
    if not condition:
        failures.append(label)


# first load: live fetches, headers are surfaced
c1 = client(cache)
data = c1.load_models()
first_calls = len(calls)
check("first load fetches over the transport", first_calls >= 2, "calls=%d" % first_calls)
check("joined dataset is non-empty", len(data["models"]) > 0)
check("rate-limit header surfaced", str(c1.rate_limit_remaining) == "97",
      "remaining=%r" % c1.rate_limit_remaining)
check("cache files written", len(list(Path(cache).glob("*.json"))) >= 2)

# second load within the TTL: zero HTTP
before = len(calls)
c2 = client(cache)
data2 = c2.load_models()
check("second load within TTL makes zero HTTP calls", len(calls) == before,
      "extra calls=%d" % (len(calls) - before))
check("cached data equals fresh data", [m["id"] for m in data2["models"]] == [m["id"] for m in data["models"]])

# --refresh forces a fetch again
before = len(calls)
c3 = client(cache, refresh=True)
c3.load_models()
check("--refresh forces a new fetch", len(calls) > before, "extra calls=%d" % (len(calls) - before))

# expired TTL forces a fetch
before = len(calls)
c4 = client(cache, ttl=0)
c4.load_models()
check("expired TTL forces a new fetch", len(calls) > before, "extra calls=%d" % (len(calls) - before))

# custom cache dir was honoured
check("cache written under --cache-dir", any(Path(cache).glob("*.json")))

# 429 surfaces Retry-After and raises (fresh cache dir so the transport is reached)
def rate_limited(url, headers):
    calls.append(url)
    return 429, {"Retry-After": "3600"}, b'{"detail":"quota exhausted"}'


rl = aa.Client(cache_dir=str(Path(cache) / "429"), transport=rate_limited,
               api_key="stub-key-not-secret")
try:
    rl.get_json("/data/llms/models")
    check("429 raises RateLimited", False, "no exception raised")
except aa.RateLimited as exc:
    check("429 raises RateLimited", True)
    check("429 message carries Retry-After", "3600" in str(exc), str(exc))

# missing key fails with a message naming both locations (config path stubbed out so a
# developer's real ~/.config/artificialanalysis/config.env cannot satisfy the lookup)
import os
saved = os.environ.pop("AA_API_KEY", None)
saved_cfg = aa.CONFIG_ENV_PATH
missing_cfg = str(Path(cache) / "no-such-config.env")
aa.CONFIG_ENV_PATH = missing_cfg
try:
    aa.resolve_api_key()
    ok = False
    message = ""
except aa.AAError as exc:
    message = str(exc)
    ok = "AA_API_KEY" in message and missing_cfg in message
finally:
    aa.CONFIG_ENV_PATH = saved_cfg
    if saved is not None:
        os.environ["AA_API_KEY"] = saved
check("missing key names AA_API_KEY and the config file", ok, message)

print("SUMMARY failures=%d" % len(failures))
sys.exit(1 if failures else 0)
PY

env -u AA_API_KEY python3 "$HELPER" "$AA" "$FIXTURES" "$TMP/cache" > "$TMP/out" 2>&1
CACHE_RC=$?
CACHE_OUT=$(cat "$TMP/out")
echo "$CACHE_OUT" | sed 's/^/    /'
assert_exit_code "cache/transport checks all pass" "$CACHE_RC" "0"
assert_contains "zero HTTP on second call" "$CACHE_OUT" "second load within TTL makes zero HTTP calls"
assert_contains "--refresh forces fetch"    "$CACHE_OUT" "--refresh forces a new fetch"

# ─── 8. no secret material ────────────────────────────────────────────────────
describe "repository hygiene"

# Assembled at runtime so this file does not itself contain the live key prefix.
SECRET_FRAGMENT="aa_""wpFC"
SECRETS=$(grep -rl "$SECRET_FRAGMENT" "$REPO_ROOT" --exclude-dir=.git 2>/dev/null | tr '\n' ' ')
assert_eq "no known API key fragment in repo" "$SECRETS" ""

SKILL_MD="$SKILL_DIR/SKILL.md"
assert_file_exists "SKILL.md exists" "$SKILL_MD"
assert_contains "SKILL.md has name frontmatter"  "$(head -5 "$SKILL_MD")" "name: artificial-analysis"
assert_contains "SKILL.md documents free tier limit" "$(cat "$SKILL_MD")" "100 requests"
assert_contains "SKILL.md documents Pro 403"     "$(cat "$SKILL_MD")" "403"
assert_contains "SKILL.md documents key paths"   "$(cat "$SKILL_MD")" "AA_API_KEY"
assert_contains "SKILL.md documents config path" "$(cat "$SKILL_MD")" "~/.config/artificialanalysis/config.env"
assert_contains "SKILL.md documents caching"     "$(cat "$SKILL_MD")" "AA_CACHE_TTL_SECS"
assert_contains "SKILL.md documents attribution" "$(cat "$SKILL_MD")" "Data: artificialanalysis.ai"

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary
