---
name: github-actions-cicd
description: Expert implementation and optimization of GitHub Actions CI/CD pipelines. Use when designing workflows, debugging pipeline failures, optimizing build times, or implementing best practices for continuous integration and deployment.
compatibility: Designed for filesystem-based agents with bash access. Requires internet connectivity for action lookups.
metadata:
  author: ai_agent_skills
  version: "1.0"
---

# GitHub Actions CI/CD Specialist

Expert guidance on implementing, debugging, and optimizing GitHub Actions workflows for CI/CD pipelines.

## When to Use This Skill

Activate this skill when the user:
- Wants to create or modify a `.github/workflows/*.yml` file
- Experiences workflow failures and needs troubleshooting help
- Asks about matrix builds, caching strategies, or secrets management
- Needs guidance on CI/CD best practices
- Wants to optimize pipeline performance

## Core Workflow Structure

### Basic Template

```yaml
name: CI Pipeline
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

env:
  NODE_ENV: production

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      
      - run: npm ci
      - run: npm test
```

## Key Implementation Guidelines

### 1. Workflow Triggers (`on`)

Choose appropriate triggers to balance responsiveness and cost:

| Trigger Type | Use Case | Example |
|-------------|----------|---------|
| `push` | Main branch deployments | `branches: [main, develop]` |
| `pull_request` | PR validation | `branches: [main]` |
| `workflow_dispatch` | Manual triggering | For ad-hoc runs |
| `schedule` | Periodic jobs | `cron: '0 0 * * *'` |

**Best Practice**: Use paths to filter irrelevant changes:
```yaml
on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - '.github/workflows/*.yml'
```

### 2. Job Configuration

Each job should have:
- **`runs-on`**: Specify runner (ubuntu-latest, windows-latest, self-hosted)
- **`timeout-minutes`**: Prevent hung jobs (recommended: 15-30 min for CI)
- **`env`**: Job-level environment variables
- **`needs`**: Dependencies on other jobs

**Example:**
```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    env:
      CI: true
    strategy:
      matrix:
        node-version: [18, 20, 22]
    steps:
```

### 3. Matrix Strategy for Parallel Testing

Use matrices to test across multiple configurations:

```yaml
strategy:
  fail-fast: false  # Continue all jobs even if one fails
  matrix:
    node-version: [18, 20, 22]
    os: [ubuntu-latest, windows-latest]
```

**Advanced Matrix Patterns:**

- **Include specific combinations**:
```yaml
strategy:
  matrix:
    include:
      - node: 20
        experimental: false
      - node: 21
        experimental: true
```

- **Dynamic matrices based on code changes**:
```yaml
# Use outputs from previous jobs to adjust matrix
if: ${{ matrix.unit-test-this-shard == 'true' }}
```

### 4. Caching Dependencies

Optimize build times with intelligent caching:

```yaml
- name: Cache node modules
  uses: actions/cache@v4
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ matrix.node-version }}-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-${{ matrix.node-version }}-
```

**Caching Best Practices:**
- Cache at the job level, before dependency installation
- Use `hashFiles()` for cache invalidation on lockfile changes  
- Include OS and runtime version in cache key to prevent conflicts
- Provide restore-keys for partial matches

### 5. Secrets Management

Proper secrets usage patterns:

**Standard approach:**
```yaml
steps:
  - name: Deploy with API key
    env:
      API_KEY: ${{ secrets.API_KEY }}
    run: ./deploy.sh
```

**In matrix strategy:**
```yaml
strategy:
  matrix:
    include:
      - org: apples
        secret_name: APPLES_API_KEY
      - org: bananas  
        secret_name: BANANAS_API_KEY
steps:
  - env:
      API_KEY: ${{ secrets[matrix.secret_name] }}
```

**Environment-level secrets:**
For deployment workflows, use GitHub Environments with protected secrets.

### 6. Permissions Configuration

Explicit permissions improve security:

```yaml
permissions:
  contents: read       # For checkout
  packages: write      # For pushing container images
  id-token: write      # For OIDC authentication
```

**Common permission combinations:**
- **Read-only CI**: `contents: read`
- **PR with comments**: `contents: read, pull-requests: write`
- **Package publishing**: `contents: write, packages: write`

## Debugging Workflow Failures

### Common Issues & Solutions

| Problem | Diagnosis | Solution |
|---------|-----------|----------|
| Job hangs/timeout | Check `timeout-minutes`, add debug logging | Increase timeout or investigate infinite loops |
| Cache misses | Inspect cache key pattern | Verify hashFiles path and key structure |
| Secret not available | Check scope (repo vs env) | Use correct secrets context or environment |
| Matrix job failures | Review fail-fast setting | Set `fail-fast: false` for complete results |
| Permission denied | Audit permissions block | Add specific permission grants |

### Debugging Techniques

**1. Enable step-level debugging:**
```yaml
env:
  ACTIONS_RUNNER_DEBUG: true
  ACTIONS_STEP_DEBUG: true
```

**2. Add diagnostic steps:**
```yaml
- name: Debug environment
  run: |
    echo "GITHUB_REF: ${{ github.ref }}"
    echo "Matrix value: ${{ matrix.os }}"
    env | sort
```

**3. Use structured logging:**
```bash
# In shell scripts
echo "::group::Setup Phase
# ... commands ...
echo ::endgroup::
```

### Workflow Validation

Use `actionlint` for syntax validation:
```bash
actionlint .github/workflows/*.yml
```

**Common linting issues:**
- Missing quotes around expressions with special characters
- Incorrect action versions (use @v4 not @main)
- Permission scope mismatches

## Performance Optimization

### Strategies to Reduce CI Time

1. **Parallel jobs**: Split independent test suites into parallel jobs
2. **Path filtering**: Only run workflows on relevant file changes  
3. **Caching**: Cache dependencies, build outputs, and generated assets
4. **Self-hosted runners**: Use faster hardware for heavy workloads
5. **Avoid redundant steps**: Don't checkout or install if not needed

### Example: Optimized Multi-Stage Pipeline

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      artifact-path: ${{ steps.build.outputs.path }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Cache deps
        uses: actions/cache@v4
        with:
          path: node_modules
          key: deps-${{ hashFiles('**/package-lock.json') }}
      
      - id: build
        run: |
          npm ci
          npm run build
          echo "path=dist/" >> $GITHUB_OUTPUT

  test:
    runs-on: ubuntu-latest  
    needs: build
    steps:
      - uses: actions/checkout@v4
      
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: build-output
          
      - run: npm test
```

## Flakiness Mitigation

For reliable CI/CD:

1. **Explicit waits** instead of arbitrary sleep times
2. **Retry logic** for transient failures:
```yaml
- uses: nick-fields/retry@v3
  with:
    timeout_minutes: 5
    max_attempts: 3
    command: npm test
```

3. **Robust selectors** in E2E tests (data-testid attributes)
4. **Test data isolation**: Create/cleanup unique data per run
5. **Avoid shared state**: Each job should be idempotent

## Workflow Templates

### Standard CI Pipeline

See `assets/templates/ci-pipeline.yml` for a production-ready template covering:
- Code checkout with sparse checkout option
- Dependency caching with lockfile hashing  
- Matrix testing across versions
- Artifact collection and upload
- Coverage reporting integration

### Multi-Environment Deployment

See `assets/templates/deploy-multi-env.yml` for:
- Environment-based secrets management
- Approval gates between stages
- Rollback strategies
- Health check validation

## Reference Files

| File | Purpose | When to Load |
|------|---------|--------------|
| [SYNTAX_REFERENCE.md](references/SYNTAX_REFERENCE.md) | Complete YAML schema reference | Building new workflows |
| [BEST_PRACTICES.md](references/BEST_PRACTICES.md) | Industry best practices | Optimizing existing pipelines |
| [TROUBLESHOOTING.md](references/TROUBLESHOOTING.md) | Debug common failure modes | Diagnosing failed runs |

## Scripts

### Analyze Workflow Performance

Run `scripts/analyze_workflow.py` to:
- Identify bottlenecks in execution time  
- Suggest caching opportunities
- Flag permission issues
- Detect anti-patterns

### Validate Syntax

Use `scripts/validate_syntax.sh` to:
- Check YAML validity
- Verify action versions
- Ensure required fields present

## Examples

### Simple CI Pipeline

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm test
```

### Matrix Build Example

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python: ['3.9', '3.10', '3.11']
    steps:
      - uses: actions/checkout@v4
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python }}
      - run: pip install -r requirements.txt
      - run: pytest tests/
```

## Activation Keywords

This skill activates when user mentions:
- "GitHub Actions workflow" or ".github/workflows"
- "CI/CD pipeline"
- "workflow file" or "action yml"  
- "matrix build" or "parallel testing"
- "debug GitHub Actions" or "pipeline failed"
- "optimize CI time" or "cache dependencies"
