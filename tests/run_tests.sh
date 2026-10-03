#!/usr/bin/env bash
# Run all install-*.sh test suites and report an aggregate result.
#
# Usage:
#   ./tests/run_tests.sh              # run all suites
#   ./tests/run_tests.sh skill        # run only test_install_skill.sh
#   ./tests/run_tests.sh agent ext    # run agent + extension suites
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_BOLD='\033[1m'
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_BLUE='\033[0;34m'
_NC='\033[0m'

# Map shorthand -> file
declare -A SUITE_FILES=(
    ["skill"]="$TESTS_DIR/test_install_skill.sh"
    ["agent"]="$TESTS_DIR/test_install_agent.sh"
    ["ext"]="$TESTS_DIR/test_install_extension.sh"
    ["devflow"]="$TESTS_DIR/test_devflow_runner.sh"
)

# Decide which suites to run
if [[ $# -gt 0 ]]; then
    SUITES=("$@")
else
    SUITES=("skill" "agent" "ext")
fi

OVERALL_PASS=0
OVERALL_FAIL=0
SUITE_RESULTS=()

for suite in "${SUITES[@]}"; do
    file="${SUITE_FILES[$suite]:-}"
    if [[ -z "$file" || ! -f "$file" ]]; then
        echo -e "${_RED}Unknown suite: $suite${_NC}  (known: skill, agent, ext)"
        exit 1
    fi

    echo -e "\n${_BOLD}${_BLUE}══════════════════════════════════════════${_NC}"
    echo -e "${_BOLD}${_BLUE}  Suite: $suite${_NC}"
    echo -e "${_BOLD}${_BLUE}══════════════════════════════════════════${_NC}"

    set +e
    bash "$file"
    rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
        SUITE_RESULTS+=("${_GREEN}✓ $suite${_NC}")
        OVERALL_PASS=$(( OVERALL_PASS + 1 ))
    else
        SUITE_RESULTS+=("${_RED}✗ $suite${_NC}")
        OVERALL_FAIL=$(( OVERALL_FAIL + 1 ))
    fi
done

echo -e "\n${_BOLD}══════════════════════════════════════════${_NC}"
echo -e "${_BOLD}  Aggregate Result${_NC}"
echo -e "${_BOLD}══════════════════════════════════════════${_NC}"
for r in "${SUITE_RESULTS[@]}"; do
    echo -e "  $r"
done
echo ""

if [[ $OVERALL_FAIL -eq 0 ]]; then
    echo -e "${_GREEN}${_BOLD}All $OVERALL_PASS suite(s) passed.${_NC}"
    exit 0
else
    echo -e "${_RED}${_BOLD}$OVERALL_FAIL suite(s) failed.${_NC}"
    exit 1
fi
