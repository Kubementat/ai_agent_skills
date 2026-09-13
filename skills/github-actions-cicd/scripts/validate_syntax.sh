#!/bin/bash
# GitHub Actions Workflow Syntax Validator
# Usage: ./validate_syntax.sh <workflow_file.yml> [actionlint_path]

set -e

WORKFLOW_FILE="${1:-.github/workflows/ci.yml}"
ACTIONLINT="${2:-actionlint}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "GitHub Actions Workflow Syntax Validator"
echo "File: ${WORKFLOW_FILE}"
echo "=========================================="
echo ""

# Check if file exists
if [[ ! -f "${WORKFLOW_FILE}" ]]; then
    echo -e "${RED}✗ File not found: ${WORKFLOW_FILE}${NC}"
    exit 1
fi

# Run actionlint if available
if command -v ${ACTIONLINT} &> /dev/null; then
    echo "Running actionlint..."
    if ${ACTIONLINT} "${WORKFLOW_FILE}" 2>&1; then
        echo -e "${GREEN}✓ actionlint passed${NC}"
    else
        echo -e "${YELLOW}⚠ actionlint found issues:${NC}"
        ${ACTIONLINT} "${WORKFLOW_FILE}" --format '{{range .}}[{{.Location.Line}}:{{.Location.Column}}] {{.Message}}{{"\n"}}{{end}}' 2>&1 || true
    fi
else
    echo -e "${YELLOW}⚠ actionlint not found, skipping advanced validation${NC}"
fi

# Basic YAML syntax check with python
echo ""
echo "Checking basic YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('${WORKFLOW_FILE}'))" 2>/dev/null; then
    echo -e "${GREEN}✓ Valid YAML syntax${NC}"
else
    echo -e "${RED}✗ Invalid YAML syntax${NC}"
    exit 1
fi

# Check for required fields
echo ""
echo "Checking required workflow fields..."

# Check 'on' trigger
if grep -q "^on:" "${WORKFLOW_FILE}" || grep -q "^  on:" "${WORKFLOWFile}" 2>/dev/null; then
    echo -e "${GREEN}✓ Workflow triggers defined${NC}"
else
    echo -e "${YELLOW}⚠ No 'on' trigger found${NC}"
fi

# Check for jobs
if grep -q "^jobs:" "${WORKFLOW_FILE}" || grep -q "  jobs:" "${WORKFLOW_FILE}" 2>/dev/null; then
    echo -e "${GREEN}✓ Jobs section present${NC}"
else
    echo -e "${RED}✗ No 'jobs' section found${NC}"
fi

# Check for common issues
echo ""
echo "Checking for common issues..."

# Tab characters (should use spaces)
if grep -q $'\t' "${WORKFLOW_FILE}"; then
    echo -e "${YELLOW}⚠ Tab characters detected (recommend spaces only)${NC}"
else
    echo -e "${GREEN}✓ No tab characters${NC}"
fi

# Check for action versions
echo ""
echo "Checking action version pins..."
grep -E "uses: .+@" "${WORKFLOW_FILE}" | while read -r line; do
    action=$(echo "$line" | sed 's/.*uses: //' | sed 's/#.*//')
    
    # Check for @main or @master
    if echo "$action" | grep -qE "@(main|master)$"; then
        echo -e "${YELLOW}⚠ Unpinned action found:${NC} ${line}"
    elif echo "$action" | grep -qE "@v[0-9]+$"; then
        echo -e "${GREEN}✓ Properly pinned:${NC} ${action}"
    else
        echo -e "${YELLOW}? Unknown version format:${NC} ${action}"
    fi
done

# Check for timeout configuration
echo ""
echo "Checking timeout configurations..."
if grep -q "timeout-minutes:" "${WORKFLOW_FILE}"; then
    job_count=$(grep -c "^  [a-z].*:" "${WORKFLOW_FILE}" || echo "0")
    timeout_count=$(grep -c "timeout-minutes:" "${WORKFLOW_FILE}")
    
    if [[ ${job_count} -eq ${timeout_count} ]]; then
        echo -e "${GREEN}✓ All jobs have timeouts${NC}"
    else
        echo -e "${YELLOW}⚠ Only ${timeout_count}/${job_count} jobs have timeout-minutes${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No timeout-minutes found (recommended for all jobs)${NC}"
fi

# Check permissions block
echo ""
echo "Checking permissions configuration..."
if grep -q "^permissions:" "${WORKFLOW_FILE}" || grep -q "  permissions:" "${WORKFLOW_FILE}" 2>/dev/null; then
    echo -e "${GREEN}✓ Permissions block present${NC}"
else
    echo -e "${YELLOW}⚠ No explicit permissions found (recommended for security)${NC}"
fi

# Environment variable check
echo ""
echo "Checking environment variables..."
if grep -q "^env:" "${WORKFLOW_FILE}" || grep -q "  env:" "${WORKFLOW_FILE}" 2>/dev/null; then
    echo -e "${GREEN}✓ Workflow-level env vars defined${NC}"
else
    echo -e "${YELLOW}⚠ No workflow-level environment variables${NC}"
fi

# Final summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo "File: ${WORKFLOW_FILE}"
echo "Lines: $(wc -l < "${WORKFLOW_FILE}")"
echo "Size: $(du -h "${WORKFLOW_FILE}" | cut -f1)"
echo ""

# Count jobs and steps
job_count=$(grep -c "^  [a-z].*:$" "${WORKFLOW_FILE}" || echo "0")
step_count=$(grep -c "^    - " "${WORKFLOW_FILE}" || echo "0")

echo "Jobs detected: ${job_count}"
echo "Steps detected: ${step_count}"
echo ""
echo -e "${GREEN}✓ Basic validation complete${NC}"