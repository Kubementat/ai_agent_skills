# AI Agent Skills and Agents Repository

This repository contains various skills, agents, extensions, and tools for AI agents, organized in a structured manner to support different capabilities and functionalities.
These are implemented to be used exclusively by AI agents like opencode, Claude Code, pi, and other compatible agents.

## Overview

This repository provides agent configurations, extensions, and specialized skills for AI coding agents including opencode, Claude Code, pi, and others. Skills cover CLI tooling, file organization, system monitoring, knowledge management, infrastructure automation, and development strategy.

## Quick Start with an AI Agent

This repository ships an [Agent Skills](https://agentskills.io)-compatible skill that gives any compatible AI agent (Claude Code, pi, etc.) full context about the available automations, how to configure them, and how to run them.

Point your agent at the skill file:
```
read the skill definition in skills/ai-agent-skills-assistant/SKILL.md and guide me through using this repository
```

The agent will read the README and discover available scripts on its own, then guide you interactively.

## Installation

### Quick Start (Recommended)

#### Installing Skills

Use the provided installation script for an easy, guided experience:

```bash
# Interactive installation wizard (recommended for first-time users)
./install-skill.sh --interactive

# show all installation options
./install-skill.sh --help
```

#### Installing Extensions

##### Extensions Disclaimer
Most of the extensions stem from the [ai-agent-extensions](https://github.com/jayshah5696/pi-agent-extensions).

For coding agent extensions:

```bash
# Interactive installation wizard (recommended)
./install-extension.sh --interactive

# show all installation options
./install-extension.sh --help
```

#### Installing Agents

For agent configurations:

```bash
# Interactive installation wizard (recommended)
./install-agent.sh --interactive

# show all installation options
./install-agent.sh --help
```

### Manual Installation

#### opencode

```bash
# Clone this repository
git clone https://github.com/julweber/ai_agent_skills
cd ai_agent_skills

# Link skills to opencode config directory
mkdir -p ~/.config/opencode/skills
ln -sf "$(pwd)/skills" ~/.config/opencode/skills
```

The linked skills will automatically be available to your opencode agent.

#### pi

```bash
# Clone this repository
git clone https://github.com/julweber/ai_agent_skills
cd ai_agent_skills

# Link skills to pi project directory
mkdir -p .pi/agent/skills
ln -sf "$(pwd)/skills" .pi/agent/skills

# Link extensions (optional)
mkdir -p .pi/agent/extensions
ln -sf "$(pwd)/extensions/pi/fetch-tool" .pi/agent/extensions/fetch-tool

# Link agents (optional)
mkdir -p .pi/agents
ln -sf "$(pwd)/agents/pi" .pi/agents/pi
```

The linked skills, extensions, and agents will automatically be available to your pi when working within this project.

#### claude

```bash
# Clone this repository
git clone https://github.com/julweber/ai_agent_skills
cd ai_agent_skills

# Link skills to Claude config directory
mkdir -p ~/.claude/skills
ln -sf "$(pwd)/skills" ~/.claude/skills
```

The linked skills will automatically be available to your Claude agent.

## Supported Agents

| Agent        | Target Directory             | Installation Type         |
|--------------|------------------------------|---------------------------|
| **opencode** | `~/.config/opencode/skills`  | Symlink (default) or Copy |
| **pi**       | `<project>/.pi/agent/skills` | Symlink (default) or Copy |
| **claude**   | `~/.claude/skills`           | Symlink (default) or Copy |
| **codex**    | Config-dependent             | Manual configuration      |

---

## Directory Structure

The repository is organized into logical sections for different agent capabilities:

- **`skills/`** — Individual skill implementations (one directory per skill with `SKILL.md` documentation and supporting scripts)
- **`agents/`** — Agent configuration templates for various coding agents (currently supports Pi)
- **`extensions/`** — Custom tool extensions that augment agent capabilities
- **`ralph/`** — Autonomous development loop implementation for opencode
- **`docs/`** — Research documents and analysis (untracked in main repo)
- **`prompts/`** — Reusable prompt templates
- **`tests/`** — Bash test suite for install scripts
- Root-level installers (`install-skill.sh`, `install-agent.sh`, `install-extension.sh`) for easy setup

## Available Skills

The repository contains skills organized by domain:

### Coding Agent CLIs
These skills provide expert control over specific coding agent CLI tools.

| Skill | Description |
|-------|-------------|
| **claude-cli** | Complete Claude Code CLI: sessions, MCP servers, plugins, authentication, all commands/flags/options |
| **codex-cli** | Codex CLI expert: exec, review, login/logout, MCP server management, sandbox modes |
| **opencode-cli** | Expert opencode CLI: TUI, server, web UI, sessions, providers, agents, models, import/export |
| **pi-cli** | Pi coding agent CLI: launch sessions, manage extensions/packages, switch models, configure tools |
| **herdr-cli** | herdr terminal workspace manager: orchestrate AI coding agents in persistent terminal sessions via UNIX socket |

### Infrastructure & DevOps CLIs
CLI skills for infrastructure management and CI/CD pipelines.

| Skill | Description |
|-------|-------------|
| **ansible** | Ansible automation: playbooks, roles, inventory; Proxmox VE and Docker integration |
| **concourse-ci** | Concourse CI/CD pipelines: pipelines, resources, jobs, worker configuration |
| **github-actions-cicd** | GitHub Actions workflows: runners, actions, deployment strategies, best practices |
| **github-cli** | GitHub CLI (gh): PRs, issues, repos, workflows, releases, programmatic JSON operations |
| **docker-cli** | Expert Docker CLI reference — containers, images, buildx, compose, networking, volumes, security, multi-platform builds, and troubleshooting |
| **terraform** | Terraform/OpenTofu: modules, testing, CI/CD, security scanning (trivy/checkov) |

### System & Productivity CLIs
CLI tools for system management and productivity.

| Skill                             | Description                                                                     |
| -----------------------------------| ---------------------------------------------------------------------------------|
| **gtd-assistant**                 | GTD productivity: open loop collection, brainstorming for actionable next steps |
| **list-large-files**              | List top N largest files in directory tree (Python-based)                       |
| **list-most-intensive-processes** | List top N processes by CPU time and memory usage                               |
| **tmux-specialist**               | Complete tmux: sessions/windows/panes, scripting, automation, plugins, config   |
| **uv**                            | uv Python manager: fast installs, virtualenvs, script execution                 |

### External Service CLIs
CLI tools for interacting with external services and platforms.

| Skill | Description |
|-------|-------------|
| **gws-cli** | Google Workspace CLI: Gmail, Drive, Calendar automation |
| **hf-cli** | Hugging Face CLI: model download/upload, inference, dataset management |
| **llama-cpp** | llama.cpp expert: llama-server, llama-cli, local LLM inference with GPU acceleration |
| **nextcloud-cli** | Nextcloud sync (nextcloudcmd): file synchronization with remote servers |
| **plnk-cli** | `plnk` CLI for self-hosted Planka kanban: projects/boards/lists/cards/tasks/comments/labels/custom fields, scoped finds, JSON output. Needs the `plnk` binary |
| **trello-cli** | Trello CLI: boards/cards/lists management via JSON operations |

### Knowledge Management
Skills for organizing and managing knowledge bases.

| Skill | Description |
|-------|-------------|
| **code-summarizer** | Codebase summarization from local dirs or GitHub/GitLab URLs |
| **morning-ritual** | ⚠️ Deprecated — replaced by **quest-system** (calendar + task collection absorbed, MITs replaced by goal-first quests) |
| **obsidian-master** | Complete Obsidian vault control via CLI: read/edit/search/links/tasks/properties/plugins |
| **obsidian-open-loops-collector** | Collect open loops from Obsidian: tasks, TODOs, dangling thoughts, stub notes |
| **quest-system** | Goal-first daily work system ("Captain's Log"): calendar + task briefing, lat economy, ranks, streaks. Replaces morning-ritual |

### Development Tools & Strategy
Skills for development workflows and strategic planning.

| Skill                         | Description                                                                                     |
| -------------------------------| -------------------------------------------------------------------------------------------------|
| **ai-agent-skills-assistant** | Navigate the AI Agent Skills repo: install skills/agents/extensions, discover capabilities      |
| **code-doctor**             | Diagnose structural codebase problems (god classes, circular deps, SOLID anti-patterns) with actionable findings and example diffs |
| **dev-brainstorming**         | Principal Engineer/Strategist: architectural ideas, feature extensions, refactoring, innovation |
| **file-organizer**            | Intelligent file/folder organization: context awareness, duplicates, structure suggestions      |
| **frontend-web-developer**    | Full-stack web dev: React, Next.js, Tailwind CSS v4, modern frontend best practices             |
| **opencode-agent-creator**    | Create/manage Opencode Agents (primary/subagents)                                               |
| **ponytail**                  | Forces the laziest working solution: YAGNI, stdlib before custom code, minimal over bloated (lite/full/ultra) |
| **pi-subagents-master**       | Create/manage pi subagent configurations and multi-agent pipelines                              |
| **product-prd-brainstorming** | Generate PRDs with Mermaid system architecture diagrams                                         |
| **python-api-developer**      | Python API development: REST, FastAPI/Flask, auth, testing, deployment                          |
| **ralph-prd-converter**       | Convert markdown PRDs to Ralph's JSON format for autonomous execution                           |
| **ralph-prd-generator**       | Generate detailed PRDs with questions, user stories, acceptance criteria                        |
| **rest-testssuite**           | REST API testsuites: organization, CRUD test file generation                                    |
| **skill-loader**              | Discover skills from custom local skill collections in specific directories                     |

---

## Agent Implementations

The `agents/pi/` directory contains specialized agent configurations for the Pi coding agent:

### Research & Analysis Agents
| Agent              | Description                                                                                                                                                                              |
| --------------------| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **summarizer**     | Research summarization and synthesis agent that processes complex documents, identifies key insights, and creates concise summaries while maintaining context and actionable takeaways   |
| **web-researcher** | Comprehensive web research and analysis agent with systematic approach to information gathering, source verification, cross-referencing, and synthesizing findings from multiple sources |

## Coding Agent Extensions

#### Available Extensions
| Extension | Description |
|-----------|-------------|
| **fetch-tool** | Hybrid URL fetching extension with automatic content detection (JSON, HTML, RSS, binary), markdown rendering, and truncation for the Pi coding agent |

## Ralph Loop Integration

The repository includes the **ralph loop** - an autonomous development system for opencode:

1. Generate PRD using `/ralph-prd-generator`
2. Convert to JSON format using `/ralph-prd-converter`
3. Run autonomous loop with `./scripts/ralph/opencode-ralph.sh`

See [ralph/README.md](ralph/README.md) for setup and usage details.

## Testing

The `tests/` directory contains a self-contained bash test suite for the three install scripts. No external dependencies are required.

```bash
# Run all suites
bash tests/run_tests.sh

# Run a single suite
bash tests/run_tests.sh skill     # install-skill.sh
bash tests/run_tests.sh agent     # install-agent.sh
bash tests/run_tests.sh ext       # install-extension.sh

# Run two suites
bash tests/run_tests.sh agent ext
```

Each suite can also be executed directly:

```bash
bash tests/test_install_skill.sh
bash tests/test_install_agent.sh
bash tests/test_install_extension.sh
```

The runner exits with code `0` when all suites pass and `1` if any suite fails.

---

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a new branch for your feature
3. Make your changes (ensure SKILL.md follows YAML frontmatter format)
4. Run `python3 -m py_compile scripts/*.py` to verify Python syntax if adding scripts
5. Submit a pull request with a clear description of your changes

## License

This project is licensed under the MIT License - see the LICENSE file for details.

# Interesting external skills
- [superpowers](https://github.com/obra/superpowers)
- [agent-skill-creator](https://github.com/FrancyJGLisboa/agent-skill-creator)
- [obsidian-skills](https://github.com/kepano/obsidian-skills)
