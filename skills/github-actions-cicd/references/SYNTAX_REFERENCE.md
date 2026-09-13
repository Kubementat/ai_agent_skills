# GitHub Actions Syntax Reference

Complete reference for GitHub Actions workflow YAML syntax.

## Workflow Structure

```yaml
name: Workflow Name  # Optional, defaults to file name
on:                  # Required - triggers
  trigger_type:
    key: value
    
permissions:         # Optional - permission grants
  scope: level
    
env:                 # Optional - environment variables
  VAR: value
    
jobs:                # Required - job definitions
  job_id:
    runs-on: runner
    steps:
      - name: Step name
        action: action@version
```

## Trigger Types

### Event Triggers

| Event | Syntax | Description |
|-------|--------|-------------|
| push | `on: push` | On any push |
| push (branch) | `on:\n  push:\n    branches: [main]` | Specific branches |
| push (path) | `on:\n  push:\n    paths: ['src/**']` | Path filter |
| pull_request | `on: pull_request` | Any PR |
| pull_request_target | `on: pull_request_target` | PR from fork |
| workflow_dispatch | `on: workflow_dispatch` | Manual trigger |
| schedule | `on:\n  schedule:\n    - cron: '0 0 * * *'` | Scheduled runs |
| release | `on:\n  release:\n    types: [published]` | Release events |

### Workflow Context Variables

```yaml
${{ github.repository }}     # Owner/repo name
${{ github.ref }}            # Ref (refs/heads/main)
${{ github.sha }}            # Commit SHA
${{ github.event_name }}     # Trigger event
${{ github.actor }}          # Username who triggered
${{ github.run_id }}         # Unique run ID
```

## Job Configuration

### Required Fields

- `runs-on`: Runner type
  - `ubuntu-latest`, `windows-latest`, `macos-latest`
  - Custom runner labels
  
### Optional Fields

| Field | Description | Example |
|-------|-------------|---------|
| `name` | Display name | `name: Build` |
| `needs` | Job dependencies | `needs: [test, lint]` |
| `if` | Conditional execution | `if: github.event_name == 'push'` |
| `timeout-minutes` | Max runtime | `timeout-minutes: 30` |
| `env` | Job env vars | `env: CI: true` |
| `strategy` | Matrix builds | See matrix section |
| `container` | Container config | `image: node:20` |
| `services` | Service containers | For Docker Compose |
| `defaults` | Default step settings | `run.shell: bash` |

## Step Types

### Using Actions

```yaml
- uses: actions/checkout@v4
  with:
    path: src
    fetch-depth: 1
    
- uses: actions/setup-node@v4
  with:
    node-version: '20'
    cache: npm
```

**Common Actions:**
- `actions/checkout@v4` - Checkout repository
- `actions/upload-artifact@v4` - Upload artifacts  
- `actions/download-artifact@v4` - Download artifacts
- `actions/cache@v4` - Cache dependencies
- `actions/setup-*` - Setup language runtimes

### Running Commands

```yaml
# Single command
- run: npm install

# Multi-line commands
- run: |
    npm ci
    npm run build
    npm test
    
# With environment variables
- name: Deploy
  env:
    API_KEY: ${{ secrets.API_KEY }}
  run: ./deploy.sh
  
# Working directory
- run: make test
  working-directory: ./backend

# Shell specification  
- run: python3 script.py
  shell: bash
```

### Using Scripts

```yaml
- name: Run custom script
  uses: ./.github/actions/custom-step
  with:
    param1: value1
    
- run: bash scripts/setup.sh
  env:
    CUSTOM_VAR: ${{ matrix.env }}
```

## Matrix Strategy

### Basic Matrix

```yaml
strategy:
  fail-fast: false
  matrix:
    os: [ubuntu-latest, windows-latest]
    node-version: [18, 20, 22]
```

Access in steps:
```yaml
- uses: actions/setup-node@v4
  with:
    node-version: ${{ matrix.node-version }}
```

### Include/Exclude Patterns

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest]
    include:
      - os: ubuntu-latest
        deploy: true
    exclude:
      - os: windows-latest
        node-version: 22
```

### Dynamic Matrix

```yaml
# Based on previous job output
needs: build-selector
if: ${{ matrix.unit-test-this-shard == 'true' }}
strategy:
  matrix:
    include: ${{ fromJson(needs.build-selector.outputs.matrix) }}
```

## Caching Syntax

### Basic Cache Step

```yaml
- name: Cache node modules
  uses: actions/cache@v4
  id: cache
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
```

### Cache Key Patterns

| Pattern | Use Case |
|---------|----------|
| `hashFiles('**/package-lock.json')` | Lockfile-based cache invalidation |
| `${{ matrix.python-version }}` | Version-specific caches |
| `${{ runner.os }}` | OS-specific caches |
| `date: ${{ github.run_number }}` | Run-number based (not recommended) |

## Secrets Management

### Basic Usage

```yaml
env:
  API_KEY: ${{ secrets.MY_API_KEY }}
  
- run: echo "Token is ${API_KEY}"
```

### In Matrix Strategy

```yaml
strategy:
  matrix:
    include:
      - env: prod
        secret: PROD_API_KEY
      - env: staging  
        secret: STAGING_API_KEY

env:
  API_KEY: ${{ secrets[matrix.secret] }}
```

## Permissions Syntax

### Workflow Level

```yaml
permissions:
  contents: read
  pull-requests: write
  packages: write
```

### Job Level (overrides workflow)

```yaml
jobs:
  deploy:
    permissions:
      id-token: write  # For OIDC
      contents: read
```

## Conditional Execution

### Branch Filters

```yaml
if: github.ref == 'refs/heads/main'
if: startsWith(github.ref, 'refs/heads/release/')
```

### Event-based

```yaml  
if: github.event_name == 'workflow_dispatch'
if: contains(github.event.pull_request.labels.*.name, 'deploy')
```

### Status Checks

```yaml
if: success()           # All previous steps succeeded
if: failure()          # Any previous step failed
if: always()           # Always run (even if cancelled)
if: cancelled()        # Job was cancelled
```

## Outputs and Data Passing

### Setting Outputs

```yaml
- id: build
  run: |
    echo "artifact-path=dist/" >> $GITHUB_OUTPUT
  
# Access in downstream jobs
needs: build
env:
  ARTIFACT_PATH: ${{ needs.build.outputs.artifact-path }}
```

### Multiple Outputs

```yaml
- id: vars
  run: |
    echo "version=1.0.0" >> $GITHUB_OUTPUT
    echo "sha=${{ github.sha }}" >> $GITHUB_OUTPUT
  
env:
  VERSION: ${{ steps.vars.outputs.version }}
```

## Annotations and Grouping

### Step Annotations

```yaml
- name: Build Application
  run: |
    echo "::group::Install Dependencies
    npm ci
    echo ::endgroup::
    
    echo "::group::Build
    npm run build  
    echo ::endgroup::"
```

### Environment Groups

```yaml
- name: Setup environment
  run: |
    echo "::add-mask::${{ secrets.API_KEY }}"
    # API_KEY is now hidden in logs
```

## Common Patterns

### Artifact Management

```yaml
# Upload
- uses: actions/upload-artifact@v4
  with:
    name: build-output
    path: dist/
    retention-days: 7
    
# Download  
- uses: actions/download-artifact@v4
  with:
    name: build-output
    path: ./downloaded/
```

### Retry Logic

```yaml
- uses: nick-fields/retry@v3
  with:
    timeout_minutes: 5
    max_attempts: 3
    command: npm test
```

### Timeout Handling

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - run: echo "Will timeout after 15 min"
```

## Error Handling

### Continue on Error

```yaml
- name: Optional step
  continue-on-error: true
  run: npm test || exit 0
  
# Or at job level
jobs:
  test:
    continue-on-error: true
```

### Failure Steps

```yaml
- name: Cleanup on failure
  if: failure()
  run: docker-compose down
```
