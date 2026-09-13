---
name: pi-cli
description: Expert control of the pi coding agent CLI. Use when the user wants to launch pi sessions, manage extensions/packages, switch models, configure tools, export sessions, resume conversations, or script pi non-interactively. Covers all flags, commands, environment variables, and usage patterns.
compatibility: Requires pi CLI installed and accessible on PATH
---

# Pi CLI

`pi` is an AI coding assistant CLI exposing read, bash, edit, and write tools. This skill covers every aspect of controlling it from the command line.

## Core Commands

```bash
# Interactive session (default)
pi

# Interactive with initial prompt
pi "Refactor the auth module"

# Non-interactive: process and exit
pi -p "List all .ts files in src/"

# Include files in prompt
pi @prompt.md @image.png "What does this do?"

# Multiple messages (interactive)
pi "Read package.json" "What dependencies do we have?"
```

## Session Management

```bash
pi --continue              # Continue previous session (-c)
pi --resume                # Pick a past session to resume (-r)
pi --session <path>        # Use a specific session file
pi --fork <path|uuid>      # Fork a session into a new one
pi --session-dir <dir>     # Custom directory for session storage
pi --no-session            # Ephemeral session (nothing saved)
pi --export session.jsonl output.html  # Export session to HTML
```

## Extension Management

```bash
pi install <source>        # Install extension source globally
pi install <source> -l     # Install locally (project-level)
pi remove <source>         # Remove extension source
pi uninstall <source>      # Alias for remove
pi update                  # Update all installed extensions
pi update <source>         # Update a specific extension
pi list                    # List installed extensions
pi config                  # Open TUI to enable/disable resources
pi <command> --help        # Help for any sub-command
```

## Model & Provider Selection

```bash
# Default provider: google
pi --provider anthropic --model claude-sonnet-4 "..."

# Provider/model shorthand (no --provider needed)
pi --model openai/gpt-4o "..."
pi --model anthropic/claude-opus-4 "..."

# Fuzzy / glob matching
pi --model "*sonnet*" "..."

# With thinking level shorthand
pi --model sonnet:high "Solve this complex problem"
pi --thinking high "..."   # off | minimal | low | medium | high | xhigh | max

# Cycle through multiple models with Ctrl+P
pi --models claude-sonnet,claude-haiku,gpt-4o
pi --models "github-copilot/*"
pi --models sonnet:high,haiku:low

# Discover available models
pi --list-models
pi --list-models sonnet
```

## Tool Configuration

Default enabled tools: `read`, `bash`, `edit`, `write`

```bash
# Full tool set
pi --tools read,bash,edit,write,grep,find,ls "..."

# Read-only (no file modifications)
pi --tools read,grep,find,ls -p "Review the code in src/"

# Disable all tools (built-in and extension)
pi --no-tools "..."
```

Available tools:
| Tool  | Description                        | Default |
|-------|------------------------------------|---------|
| read  | Read file contents                 | ✅      |
| bash  | Execute bash commands              | ✅      |
| edit  | Edit files with find/replace       | ✅      |
| write | Write files (creates/overwrites)   | ✅      |
| grep  | Search file contents (read-only)   | ❌      |
| find  | Find files by glob (read-only)     | ❌      |
| ls    | List directory contents (read-only)| ❌      |

## Skills, Extensions & Themes

```bash
# Load specific skill(s)
pi --skill /path/to/skill-dir "..."
pi --skill /path/to/skill1 --skill /path/to/skill2 "..."

# Disable automatic skill discovery
pi --no-skills "..."           # -ns shorthand

# Load extension(s) explicitly
pi --extension /path/to/ext.js "..."   # -e shorthand
pi -e ext1.js -e ext2.js "..."

# Disable automatic extension discovery
pi --no-extensions "..."       # -ne shorthand

# Load prompt template(s)
pi --prompt-template /path/to/template "..."

# Disable automatic prompt template discovery
pi --no-prompt-templates "..."  # -np shorthand

# Load theme(s)
pi --theme /path/to/theme "..."

# Disable automatic theme discovery
pi --no-themes "..."
```

## System Prompt Control

```bash
pi --system-prompt "You are a Rust expert. ..."
pi --append-system-prompt "Always add tests for new code."
# Can also point to a file:
pi --append-system-prompt @extra-instructions.md
```

## Output Modes

```bash
pi --mode text   # Default: human-readable output
pi --mode json   # JSON-structured output
pi --mode rpc    # RPC protocol (for tool integrations)
```

## Misc Flags

```bash
pi --api-key <key>     # Override API key (defaults to env vars)
pi --verbose           # Force verbose startup output
pi --offline           # Disable startup network ops (same as PI_OFFLINE=1)
pi --version           # Show version number
pi --help              # Show full help
```

## Extension-Specific Flags

Some extensions register their own flags to the `pi` CLI:

```bash
# Enable per-session control sockets
pi --session-control "..."

# Specify a custom MCP configuration file
pi --mcp-config /path/to/mcp-config.json "..."
```

## Environment Variables

| Variable                        | Purpose                                         |
|---------------------------------|-------------------------------------------------|
| `ANTHROPIC_AUTH_TOKEN`          | Anthropic bearer auth token                     |
| `ANTHROPIC_API_KEY`             | Anthropic Claude API key                        |
| `ANTHROPIC_OAUTH_TOKEN`         | Anthropic OAuth token (alternative to API key)  |
| `OPENAI_API_KEY`                | OpenAI GPT API key                               |
| `AZURE_OPENAI_API_KEY`          | Azure OpenAI API key                              |
| `AZURE_OPENAI_BASE_URL`         | Azure OpenAI base URL                              |
| `AZURE_OPENAI_RESOURCE_NAME`    | Azure OpenAI resource name                         |
| `AZURE_OPENAI_API_VERSION`      | Azure OpenAI API version (default: v1)             |
| `AZURE_OPENAI_DEPLOYMENT_NAME_MAP` | Azure OpenAI model=deployment map                |
| `GEMINI_API_KEY`                | Google Gemini API key                           |
| `GROQ_API_KEY`                  | Groq API key                                    |
| `CEREBRAS_API_KEY`              | Cerebras API key                                 |
| `OPENROUTER_API_KEY`            | OpenRouter API key                              |
| `XAI_API_KEY`                   | xAI Grok API key                                |
| `MISTRAL_API_KEY`               | Mistral API key                                 |
| `MINIMAX_API_KEY`               | MiniMax API key                                  |
| `OPENCODE_API_KEY`              | OpenCode Zen/OpenCode Go API key                  |
| `KIMI_API_KEY`                  | Kimi For Coding API key                           |
| `AI_GATEWAY_API_KEY`            | Vercel AI Gateway API key                         |
| `ZAI_API_KEY`                   | ZAI API key                                      |
| `AWS_PROFILE` / `AWS_REGION`    | Amazon Bedrock credentials                        |
| `AWS_ACCESS_KEY_ID`             | Amazon Bedrock Access Key                          |
| `AWS_SECRET_ACCESS_KEY`         | Amazon Bedrock Secret Key                          |
| `AWS_BEARER_TOKEN_BEDROCK`      | Bedrock API key (bearer token)                    |
| `PI_CODING_AGENT_DIR`           | Session storage dir (default: `~/.pi/agent`)    |
| `PI_PACKAGE_DIR`                | Override package directory (Nix/Guix)           |
| `PI_OFFLINE`                    | Set to `1`/`true`/`yes` to disable network ops  |
| `PI_TELEMETRY`                  | Override install telemetry (1/true or 0/false)   |
| `PI_SHARE_VIEWER_URL`           | Base URL for `/share` command (default: https://pi.dev/session/) |
| `PI_AI_ANTIGRAVITY_VERSION`     | Override Antigravity User-Agent version         |

## Common Patterns

### Scripting / Automation

```bash
# Run a task and capture output (non-interactive)
pi -p --mode json "Summarize src/auth.ts" > summary.json

# Pipe a generated prompt
echo "Explain this error: $(cat error.log)" | xargs pi -p

# Combine with --no-session for isolated one-shots
pi -p --no-session "Generate a UUID"
```

### Code Review Pipeline

```bash
# Read-only review, no mutations possible
pi --tools read,grep,find,ls -p @PR_DIFF.patch "Review this PR for security issues"
```

### Locked-down Model Run

```bash
pi --model anthropic/claude-opus-4:high \
   --thinking high \
   --no-extensions \
   --no-skills \
   -p "Solve the following algorithm problem: ..."
```

### Resuming & Branching Conversations

```bash
# Resume the most recent session and continue
pi -c "Now add unit tests for what we built"

# Fork a past session to explore a different direction
pi --fork abc123 "Try a different approach using Redis instead"
```

### Export Session to HTML

```bash
pi --export ~/.pi/agent/sessions/my-session/session.jsonl
pi --export session.jsonl report.html
```
