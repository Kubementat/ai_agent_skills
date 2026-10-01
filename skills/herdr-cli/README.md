# herdr-cli

Skill for driving [herdr](https://github.com/herdr) — a terminal workspace manager
that hosts AI coding agents (pi, Claude Code, Codex, opencode, …) in persistent
terminal sessions behind a UNIX socket. Includes helper scripts for one-shot agent
launches and `runagent` for profiled, sandboxed subagents.

## Requirements

- `herdr` installed and on `PATH` (`herdr status` to check)
- `jq`, `bash`, `python3` (stdlib only)
- Agent binaries you want to run (`pi`, `claude`, `opencode`, …) — installed and authenticated
- For sandboxed profiles (`runagent`): `asb` (bubblewrap-based agent sandbox) on `PATH`

## Install

1. Copy/symlink this directory into your agent's skill dir, e.g.
   `~/.pi/agent/skills/herdr-cli` (pi auto-discovers it).
2. For `runagent` (optional):
   `ln -s "$PWD/scripts/runagent" ~/.local/bin/runagent`
3. Optional, better agent status tracking:
   `herdr integration install pi` (and/or `claude`, `opencode`, …)

## Usage

### One-shot agent tasks (helper scripts)

```bash
scripts/run-pi-herdr.sh       -m "dgx/qwen3.8-27b"   -p "Explain src/main.ts"
scripts/run-claude-herdr.sh   -m opus                -p "Refactor the auth module"
scripts/run-opencode-herdr.sh -m "anthropic/claude-sonnet-4-5" -p "Review the diff"
scripts/pipeline-herdr.sh     /path/to/repo "Add retry with backoff"   # research→plan→implement→review
```

Common flags: `-m` model, `-p` prompt, `-c` cwd, `-w` timeout (ms),
`--no-wait`, `--no-keep`. Run any script with `--help` for the full list.

### Profiled, sandboxed subagents (`runagent`)

Roles are defined as agent files in `~/.pi/agent/agents/<name>.md` (system prompt
body + frontmatter allowlists for `tools`, `skills`, `extensions`, `mcp`, `sandbox`).
Everything is fail-closed: an allowlist is exact, nothing is inherited.

```bash
runagent --list                        # available profiles
runagent web-researcher --explain      # audit the exact composed command (y/N)
runagent web-researcher -p "Research X"                # one-shot, sandboxed (ASB)
runagent web-researcher -m evo/qwen3.6-35b -w /tmp/out # overrides
runagent web-researcher                # interactive (attaches TUI, tty only)
```

The sandbox (on by default) makes the workspace the only writable dir;
`sandbox: off` in the profile opts out. Exit codes: `0` ok, `2` usage,
`10` launch, `11` timeout, `12` profile resolution, `13` herdr down.

### Raw herdr CLI

```bash
herdr server                          # start (or: herdr status)
herdr workspace create --label demo --cwd $PWD
herdr agent start my-agent --kind pi --pane <pane_id> -- --model <model>
herdr agent prompt my-agent "task" --wait --timeout 60000
herdr agent read my-agent --source recent --lines 100
```

## More

- `SKILL.md` — full agent-facing guide (workflow, gotchas, `runagent` profile format)
- `references/cli-reference.md` — complete herdr CLI surface
- `references/reference.md` — integrations, lifecycle API, configuration
- `ARCHITECTURE.md` — herdr hierarchy (session → workspace → tab → pane → agent)
