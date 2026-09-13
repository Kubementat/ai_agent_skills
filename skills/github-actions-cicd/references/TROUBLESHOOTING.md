# GitHub Actions Troubleshooting Guide

Common failure modes and debugging strategies for CI/CD pipelines.

## Workflow Syntax Errors

### YAML Parsing Issues

**Problem:** `SyntaxError: Bad indentation`

**Diagnosis:**
```bash
# Use actionlint
actionlint .github/workflows/*.yml

# Or yaml-lint
yamllint .github/workflows/*.yml
```

**Common Causes:**
1. Inconsistent indentation (mix tabs/spaces)
2. Missing quotes around special characters
3. Colon in unquoted string value

**Fix:**
```yaml
# Bad
env:
  API_KEY: ${{ secrets.API-KEY }}  # Hyphen needs quotes
  
# Good  
env:
  API_KEY: ${{ secrets.API-KEY }}  # Or quote the whole expression
  MESSAGE: "Hello World"           # Quotes around strings with spaces
```

### Expression Context Errors

**Problem:** `ReferenceError: matrix is not defined`

**Cause:** Accessing matrix outside of strategy context or wrong scope.

**Fix:**
```yaml
# Bad - trying to use matrix in job level env
jobs:
  test:
    env:
      NODE_VER: ${{ matrix.node-version }}  # Not yet available
    strategy:
      matrix:
        node-version: [18, 20]

# Good - access in step level  
jobs:
  test:
    strategy:
      matrix:
        node-version: [18, 20]
    steps:
      - env:
          NODE_VER: ${{ matrix.node-version }}
        run: echo $NODE_VER
```

## Secret Management Issues

### Secret Not Available in Matrix

**Problem:** `Error: secret 'API_KEY' not found`

**Cause:** Secrets don't automatically expand in matrix context.

**Fix:**
```yaml
# Bad - direct secret reference  
strategy:
  matrix:
    include:
      - env: prod
        api_key: ${{ secrets.PROD_API }}  # Won't work

# Good - use variable mapping
strategy:
  matrix:
    include:
      - env: prod
        secret_name: PROD_API_KEY
env:
  API_KEY: ${{ secrets[matrix.secret_name] }}
```

### Environment Secrets Not Found

**Problem:** `Error: environment 'production' not found`

**Cause:** Environment not created in repo settings or wrong name.

**Diagnosis:**
1. Check GitHub UI: Settings > Environments
2. Verify exact spelling (case-sensitive)
3. Ensure secrets are added to correct scope

## Caching Problems

### Cache Miss Despite Correct Key

**Problem:** Cache always misses, dependencies reinstall every run

**Common Causes:**

1. **Path mismatch** - Cache path doesn't match actual location
```yaml
# Bad - wrong path
- uses: actions/cache@v4
  with:
    path: node_modules  # Usually in ~/.npm for npm
    
# Good - use correct package manager cache dir  
- uses: actions/cache@v4
  with:
    path: ~/.npm        # For npm
    key: ${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
```

2. **Key collision** - Multiple jobs overwriting same cache
```yaml
# Bad - identical keys across matrix
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: node-cache  # All versions use same key
    
# Good - version-specific keys  
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: ${{ runner.os }}-${{ matrix.node-version }}-${{ hashFiles('**/package-lock.json') }}
```

3. **Lockfile changes not detected**
```yaml
# Bad - only checks package.json  
key: node-${{ hashFiles('package.json') }}

# Good - check lockfile  
key: node-${{ hashFiles('**/package-lock.json') }}
```

### Cache Size Limit Exceeded

**Problem:** `Cache size 2.1GB exceeds limit of 10GB`

**Solution:** Prune old caches or use more specific keys
```yaml
# Add timestamp to invalidate old caches  
key: ${{ runner.os }}-${{ matrix.node-version }}-${{ hashFiles('**/package-lock.json') }}-${{ github.run_number }}
```

## Timeout Issues

### Job Hangs Without Error

**Problem:** Job runs indefinitely, eventually times out

**Diagnosis Steps:**

1. **Enable debug logging**
```yaml
env:
  ACTIONS_RUNNER_DEBUG: true
  ACTIONS_STEP_DEBUG: true
steps:
  - run: npm test
```

2. **Add progress indicators**
```yaml
- run: |
    for i in {1..10}; do
      echo "Processing batch $i..."
      npm run process-batch-$i
      # Prevents timeout from no output
    done
```

3. **Check for infinite loops in scripts**
```bash
# Add timing to long steps
- name: Run E2E tests
  run: |
    START=$(date +%s)
    npm run e2e
    END=$(date +%S)  
    echo "Completed in $((END - START)) seconds"
```

### Intermittent Timeouts

**Problem:** Jobs fail randomly after ~14 minutes

**Cause:** Runner timeout or network issues

**Fixes:**
- Increase `timeout-minutes` on job
- Add retry logic for flaky operations
- Check runner health logs

## Permission Denied Errors

### Action Permission Issues

**Problem:** `Error: Resource not accessible by integration`

**Common Causes:**

1. **Missing permission grant**
```yaml
# Bad - trying to comment on PR without permission
permissions:
  contents: read
  
- uses: actions/github-script@v7
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        body: 'Tests passed!'
      })

# Good - add pull-requests permission  
permissions:
  contents: read
  pull-requests: write
```

2. **Wrong token scope**
```yaml
# Bad - GITHUB_TOKEN can't access org-level secrets
env:
  API_KEY: ${{ secrets.ORG_API }}

# Good - use explicit secret or env var  
env:
  API_KEY: ${{ vars.ORG_API }}  # Or pass as input
```

### Self-Hosted Runner Permissions

**Problem:** Permission denied when accessing files/directories

**Diagnosis:**
```bash
# Check runner user context
whoami
ls -la /path/to/dir
```

**Fix:** Adjust directory permissions or use `runas` option

## Matrix Build Failures

### fail-fast Stops All Jobs

**Problem:** One matrix job fails, all others stop prematurely

**Diagnosis:** Default `fail-fast: true` behavior

**Fix:**
```yaml
strategy:
  fail-fast: false  # Continue all jobs even if one fails
  matrix:
    os: [ubuntu-latest, windows-latest]
    node-version: [18, 20]
```

### Matrix Variable Not Available

**Problem:** `matrix.* undefined` in step context

**Cause:** Trying to access matrix before it's defined or wrong nesting

**Fix:**
```yaml
# Bad - accessing before checkout
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest]
    steps:
      - uses: actions/checkout@v4
        with:
          path: ${{ matrix.os }}  # Works, but confusing

# Good - use clear variable names  
jobs:
  test:
    strategy:
      matrix:
        platform: ubuntu-latest
    steps:
      - run: echo "Running on ${{ matrix.platform }}"
```

## Dependency Installation Issues

### npm/yarn Cache Corruption

**Problem:** `EACCES: permission denied` or corrupt cache errors

**Solution:** Clean cache between runs
```yaml
- name: Clean and install
  run: |
    rm -rf node_modules
    rm -rf ~/.npm/cache
    npm ci
```

### Lockfile Mismatch

**Problem:** `Lockfile does not match package.json`

**Causes:**
1. Different Node versions between lock generation and install
2. Mixed package manager usage (yarn vs npm)

**Fix:**
```yaml
- uses: actions/setup-node@v4
  with:
    node-version: '20'  # Match version used to generate lockfile
    
- run: npm ci --strict-peer-deps
```

## Artifact Issues

### Upload Fails with "Path not found"

**Problem:** `Error: Could not find path: dist/`

**Diagnosis:**
1. Check working directory
2. Verify build actually created files
3. Use absolute paths or correct relative paths

**Fix:**
```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - run: npm run build
        working-directory: ./frontend  # Set context correctly
        
      - name: Upload artifact  
        uses: actions/upload-artifact@v4
        with:
          name: frontend-build
          path: frontend/dist/  # Match actual output location
```

### Artifact Download Returns Empty

**Problem:** Downloaded files are empty or missing

**Causes:**
1. Different runner OS (case-sensitive paths)
2. File was deleted before upload
3. Path pattern didn't match any files

**Debug:**
```yaml
- name: Debug artifact contents
  run: |
    echo "=== Current directory ==="
    pwd
    ls -la
    
    echo "=== Artifact path ==="  
    find ./dist -type f
```

## Network & External Service Issues

### API Rate Limits

**Problem:** `429 Too Many Requests` from GitHub API or other services

**Solution:** Add retry logic and exponential backoff
```yaml
- name: Fetch release notes
  uses: octokit/request-action@v2.x
  with:
    route: GET /repos/${{ github.repository }}/releases/latest
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

# Or use retry wrapper  
- uses: nick-fields/retry@v3
  with:
    max_attempts: 5
    wait_seconds: 2
    command: curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/...
```

### Docker Pull Failures

**Problem:** `error pulling image: timeout`

**Solutions:**
1. Use specific image tags (not latest)
2. Add retry logic
3. Pre-pull images in separate step
4. Check network connectivity on runner

## Debugging Techniques by Failure Type

### Silent Failures

Add diagnostic steps before suspected failure point:
```yaml
- name: 🔍 Pre-flight check
  run: |
    echo "=== Environment ==="
    env | sort
    
    echo "=== Disk Space ==="  
    df -h
    
    echo "=== Dependencies ==="
    npm list --depth=0 2>&1 || true
```

### Intermittent Failures

Enable verbose logging:
```yaml
env:
  VERBOSE: true
  DEBUG: '*'
  
- name: Run tests with debug
  run: |
    set -x  # Print commands before executing
    npm test -- --verbose
```

### Permission Issues

Check effective permissions:
```yaml
- name: 🔍 Check permissions
  run: |
    echo "User: $(whoami)"
    echo "Groups: $(id)"
    ls -la $GITHUB_WORKSPACE
```

## Common Error Messages & Fixes

| Error Message | Likely Cause | Solution |
|---------------|--------------|----------|
| `Reference to undefined context` | Wrong expression syntax | Quote expressions, check context availability |
| `Secrets are not available` | Scope mismatch (repo vs env) | Verify secret location and environment config |
| `Cache key collision detected` | Non-unique cache keys | Add version/OS/hashFiles to key |
| `Job exceeded timeout` | Infinite loop or hung process | Set `timeout-minutes`, add progress logs |
| `Permission denied: /path/to/file` | Runner user mismatch | Adjust permissions or use correct runner |
| `Matrix variable undefined` | Wrong scope or nesting | Access matrix in step context, not job level |
| `Artifact path not found` | Working directory issue | Set proper `working-directory` or use absolute paths |

## Recommended Debugging Workflow

1. **Enable step debugging**
   ```yaml
   env:
     ACTIONS_STEP_DEBUG: true
   ```

2. **Add diagnostic steps before failures**
   - Environment variables dump
   - File system state  
   - Dependency versions

3. **Check logs systematically**
   - Runner startup logs
   - Step execution output
   - Action-specific logs (if available)

4. **Reproduce locally if possible**
   ```bash
   # Use act to run workflow locally
   act push -j build --verbose
   ```

5. **Isolate the failure**
   - Comment out steps incrementally  
   - Run jobs independently
   - Test with minimal configuration first

## Tools for Workflow Analysis

### actionlint
```bash
# Install
brew install actionlint

# Validate workflow
actionlint .github/workflows/ci.yml
```

### act (local execution)
```bash
# Install
brew install act

# Run specific job locally  
act push -j build --verbose
```

### GitHub CLI
```bash
# Check recent runs
gh run list --limit 10

# View logs for failed run
gh run view <run-id> --log

# Watch a workflow
gh run watch
```