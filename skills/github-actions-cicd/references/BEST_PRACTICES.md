# GitHub Actions CI/CD Best Practices

Industry best practices for reliable, efficient CI/CD pipelines.

## Performance Optimization

### 1. Minimize Workflow Execution Time

**Parallelize Independent Jobs**
```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm run lint
      
  test:
    runs-on: ubuntu-latest  
    steps:
      - uses: actions/checkout@v4
      - run: npm test
      
  build:
    needs: [lint, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm run build
```

**Use Path Filtering**
```yaml
on:
  push:
    paths-ignore:
      - '**.md'
      - 'docs/**'
  pull_request:
    paths:
      - 'src/**'
      - '.github/workflows/*.yml'
```

### 2. Intelligent Caching Strategy

**Cache Dependencies Early**
```yaml
jobs:
  test:
    strategy:
      matrix:
        node-version: [18, 20, 22]
    steps:
      - uses: actions/checkout@v4
      
      - name: Cache dependencies
        uses: actions/cache@v4
        with:
          path: ~/.npm
          key: ${{ runner.os }}-node-${{ matrix.node-version }}-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-${{ matrix.node-version }}-
            
      - run: npm ci  # Fast install from cache
```

**Multi-Layer Caching Pattern**
```yaml
# Layer 1: Global tool cache (npm, yarn, pip)
- uses: actions/cache@v4
  with:
    path: ~/.cache
    key: global-cache-${{ hashFiles('global.lock') }}

# Layer 2: Project dependencies  
- uses: actions/cache@v4
  with:
    path: node_modules
    key: project-cache-${{ hashFiles('**/package-lock.json') }}
```

### 3. Optimize Checkout Performance

**Sparse Checkout for Monorepos**
```yaml
- uses: actions/checkout@v4
  with:
    sparse-checkout: |
      packages/frontend
      .github/workflows
    fetch-depth: 1  # Only latest commit
```

**Shallow Clone for CI**
```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 1  # Faster, no history needed
```

## Reliability Best Practices

### 1. Handle Flaky Tests

**Retry Mechanism**
```yaml
- name: Run E2E tests
  uses: nick-fields/retry@v3
  with:
    timeout_minutes: 10
    max_attempts: 3
    command: npm run e2e
```

**Test Sharding**
```yaml
strategy:
  matrix:
    shard: [1, 2, 3]
env:
  SHARD_INDEX: ${{ matrix.shard }}
  TOTAL_SHARDS: 3
  
- run: |
    npm test -- --shard=${{ env.SHARD_INDEX }}/${{ env.TOTAL_SHARDS }}
```

### 2. Prevent Pipeline Hangs

**Set Timeouts**
```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 30  # Kill after 30 min
    
  deploy:
    needs: build
    timeout-minutes: 15
```

**Add Heartbeats for Long Jobs**
```yaml
- run: |
    echo "Starting long process..."
    for i in {1..100}; do
      npm run build-step-$i
      # Progress indicator prevents timeout
      if (( $i % 20 == 0 )); then
        echo "::notice::Completed step $i"
      fi
    done
```

### 3. Idempotent Jobs

Each job should be runnable multiple times with same result:
- Use unique test data per run (`${{ github.run_id }}`)
- Clean up resources in `if: always()` steps
- Avoid shared state between jobs

## Security Best Practices

### 1. Explicit Permissions

**Workflow Level**
```yaml
permissions:
  contents: read       # For checkout
  pull-requests: write # For PR comments
  checks: write        # For test reporting
```

**Avoid Wildcard Permissions**
```yaml
# Good
permissions:
  contents: read
  packages: write

# Bad - too permissive
permissions: write-all
```

### 2. Secrets Management

**Environment-Specific Secrets**
```yaml
jobs:
  deploy-prod:
    environment: production
    steps:
      - env:
          API_KEY: ${{ secrets.PROD_API_KEY }}
        run: ./deploy.sh
```

**Mask Sensitive Values**
```yaml
- run: |
    echo "::add-mask::${{ secrets.DEPLOY_TOKEN }}"
    export DEPLOY_TOKEN="${{ secrets.DEPLOY_TOKEN }}"
```

### 3. Pin Action Versions

**Use SHA Pins for Critical Workflows**
```yaml
# Instead of @v4
- uses: actions/checkout@1b9ec64b7387945f0a4eec2e9b8d0f5c6e5c7a2c

# Or at least use specific version
- uses: actions/checkout@v4.1.0
```

## Cost Optimization

### 1. Reduce Runner Minutes

**Skip Unnecessary Runs**
```yaml
on:
  push:
    branches: [main]
    paths-ignore:
      - '**.md'
      - '.gitignore'
```

**Conditional Job Execution**
```yaml
jobs:
  deploy-prod:
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh
```

### 2. Efficient Artifact Management

**Limit Retention**
```yaml
- uses: actions/upload-artifact@v4
  with:
    name: build-output
    path: dist/
    retention-days: 3  # Auto-cleanup after 3 days
```

**Compress Artifacts**
```yaml
- run: |
    tar -czf artifact.tar.gz dist/
    
- uses: actions/upload-artifact@v4
  with:
    name: build-output
    path: artifact.tar.gz
```

## Maintainability Best Practices

### 1. Workflow Reusability

**Reusable Workflows**
```yaml
# .github/workflows/test.yml
name: Test Suite
on:
  workflow_call:
    inputs:
      node-version:
        required: true
        type: string
        
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
      - run: npm test
```

**Call Reusable Workflow**
```yaml
jobs:
  test-18:
    uses: ./.github/workflows/test.yml
    with:
      node-version: '18'
      
  test-20:
    uses: ./.github/workflows/test.yml  
    with:
      node-version: '20'
```

### 2. Modular Design

**Split Complex Workflows**
```yaml
# Main workflow
jobs:
  build:
    uses: ./.github/workflows/build.yml
  
  test:
    needs: build
    uses: ./.github/workflows/test.yml
    
  deploy:
    needs: [build, test]
    uses: ./.github/workflows/deploy.yml
```

### 3. Documentation Within Workflow

**Add Comments and Names**
```yaml
jobs:
  # Step 1: Checkout code and setup environment
  setup:
    runs-on: ubuntu-latest
    steps:
      - name: 📦 Checkout repository
        uses: actions/checkout@v4
        
      - name: 🔧 Setup Node.js v20
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          
  # Step 2: Install dependencies and run tests  
  test:
    needs: setup
    steps:
      - name: 📦 Download cached dependencies
        uses: actions/cache@v4
        id: cache
        
      - name: 🧪 Run test suite
        run: npm test
```

## Monitoring & Observability

### 1. Add Diagnostic Steps

**Environment Inspection**
```yaml
- name: 🔍 Debug environment info
  if: failure() || always()
  run: |
    echo "=== Runner Info ==="
    echo "OS: ${{ runner.os }}"
    echo "Runner ID: ${{ runner.id }}"
    echo ""
    echo "=== Git Info ==="
    echo "Ref: ${{ github.ref }}"
    echo "SHA: ${{ github.sha }}"
    echo "Actor: ${{ github.actor }}"
    echo ""
    echo "=== Matrix Vars ==="
    env | grep -i matrix || echo "No matrix vars"
```

**Performance Timing**
```yaml
- name: ⏱️ Record step timing
  run: |
    START=$(date +%s)
    # ... your commands ...
    END=$(date +%s)
    echo "::notice::Step completed in $((END - START)) seconds"
```

### 2. Notifications on Failure

**Slack Integration**
```yaml
- name: 📢 Notify Slack on failure
  if: failure()
  uses: rtCamp/action-slack-notify@v2
  env:
    SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}
    SLACK_MESSAGE: "Workflow failed: ${{ github.repository }} @ ${{ github.ref }}"
```

## Common Anti-Patterns to Avoid

### ❌ Bad: Logic in Workflow YAML

```yaml
# Bad - complex logic inline
- run: |
    if [ "${{ matrix.os }}" == "ubuntu-latest" ] && \
       [ "${{ matrix.node-version }}" == "20" ]; then
      npm run e2e
    else  
      npm test
    fi

# Good - move to shell script
- run: bash scripts/run-tests.sh ${{ matrix.os }} ${{ matrix.node-version }}
```

### ❌ Bad: No Timeouts

```yaml
# Bad - can hang forever
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: npm run build

# Good - bounded execution  
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - run: npm run build
```

### ❌ Bad: Over-Caching

```yaml
# Bad - too broad cache key
- uses: actions/cache@v4
  with:
    path: node_modules
    key: node-cache

# Good - specific invalidation  
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: ${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
```

### ❌ Bad: Unnecessary Artifacts

```yaml
# Bad - upload everything
- uses: actions/upload-artifact@v4
  with:
    name: full-build
    path: ./

# Good - specific outputs  
- uses: actions/upload-artifact@v4
  with:
    name: dist-files
    path: dist/*.js
```

## Version Recommendations (2025-2026)

| Action | Recommended Version | Notes |
|--------|-------------------|-------|
| checkout | @v4 or @v5 | v5 adds sparse-checkout improvements |
| setup-node | @v4 | Supports Node 20+ natively |
| cache | @v4 | Stable, reliable |
| upload-artifact | @v4 | v3 has known issues |
| download-artifact | @v4 | Match upload version |

## Checklist for New Workflows

- [ ] Explicit `permissions` block defined
- [ ] All jobs have `timeout-minutes` set  
- [ ] Dependencies cached with proper keys
- [ ] Secrets scoped appropriately (env vs repo)
- [ ] Actions pinned to specific versions or SHA
- [ ] Path filters configured for efficiency
- [ ] Failure notifications configured
- [ ] Diagnostic steps added for debugging
- [ ] Matrix strategy used when beneficial
- [ ] Reusable workflows extracted where possible
