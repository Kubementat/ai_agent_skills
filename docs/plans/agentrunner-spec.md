# `runagent` — Named Agent Profiles for Sandboxed Subagent Launches

**Status:** Approved spec (brainstormed 2026-10-01, all design branches resolved)
**Scope:** v1 — pi harness only, ASB filesystem sandboxing, herdr launch orchestration

---

## 1. Goal

Run named agent *roles* (system prompt + skills + tools + extensions + MCP + sandbox
policy) as sandboxed subagents via a single CLI:

```bash
runagent web-researcher -p "Research X"          # one-shot, sandboxed
runagent web-researcher                          # interactive (attaches TUI)
runagent web-researcher -m evo/qwen3.6-35b -w /tmp/scratch -p "..."
```

The role is defined **once** in the existing pi agent files
(`~/.pi/agent/agents/*.md`) and is the same role whether it runs sandboxed on pi today
or on another harness later. The pi-native `subagent` tool path is being deprecated in
favor of this; the agent files remain the single source of truth.

### Design decisions (locked)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Unit of identity | Reuse + extend `~/.pi/agent/agents/*.md` frontmatter. One file, both paths. |
| 2 | Profile parsing | python3 (no new dependencies) |
| 3 | Skills semantics | Fail-closed allowlist: absent `skills:` = no skills; `skills: [all]` = auto-discovery. `--no-skills` always passed for explicit lists. Unknown skill name = hard fail. |
| 4 | CLI name | `runagent` |
| 5 | Model/workspace override | `-m` and `-w` flags, always allowed (model override is never policy-blocked) |
| 6 | Mode duality | With `-p` → one-shot (launch, wait, print output). Without `-p` → interactive attach (tty only). |
| 7 | cwd/workspace defaults | No `-c`/`-w` → both = shell's current dir. `-c` and `-w` stay separate flags (read-everywhere / write-only-workspace). |
| 8 | `--explain` | Prints composed launch command, asks `Proceed? [y/N]`, executes on yes |
| 9 | Harness | v1: `harness: pi` only. `--harness` exists, errors for others ("only pi supported in v1") |
| 10 | Sandbox posture | ON by default for every profile. `sandbox: off` = only opt-out. Writable dir defaults to cwd. Single writable dir (asb v1 limit — TODO in vault). Filesystem-only isolation in v1 (no network egress control). |
| 11 | MCP | Fail-closed allowlist. Filtered temp config generated from `~/.pi/agent/mcp-adapter.json` (server `env` blocks travel with the server). Absent `mcp:` = explicit empty config. `mcp: [all]` = use global config (omit `--mcp-config`). |
| 12 | Tools | Existing `tools:` key, incl. `mcp:server/tool` syntax → translated to pi's `mcp__server__tool` naming for `--tools`. |
| 13 | Extensions | Fail-closed allowlist (same pattern as skills). Absent = `--no-extensions` with nothing; `[all]` = auto-discovery. No hardcoded infra list in v1 (watch item §9). |
| 14 | Agent-session interface | `runagent` must be callable from inside an agent session: non-tty ⇒ one-shot only, clean pipeable stdout, stable exit codes. |
| 15 | Workspace lifecycle | Label `ra-<agent>-<4-digit-suffix>`. No auto-GC in v1. `--keep` default; finish prints close/attach hints. |
| 16 | Prompt input | `-p <text>`, `-p @file`, `-p -` (stdin) |
| 17 | Model validation | No pre-flight check; malformed model fails fast at pi launch |
| 18 | Placement | Code in herdr-cli skill `scripts/`; binary symlink `~/.local/bin/runagent`; docs in herdr-cli `SKILL.md` |

---

## 2. Profile format

Location: `~/.pi/agent/agents/<name>.md` (existing files, extended frontmatter).

```yaml
---
name: web-researcher
description: One-line role description (existing)
harness: pi                      # v1: only "pi" accepted
model: dgx/qwen3.8-27b           # default model, provider/model format; -m overrides
tools: read, bash, fetch, mcp:brave-search/brave_web_search
skills: [web-research]           # absent → none; [all] → auto-discovery
extensions: [pi-mcp-adapter]     # absent → none; [all] → auto-discovery
mcp: [brave-search]              # absent → empty; [all] → global config
sandbox: on                      # default; `sandbox: off` opts out
  workspace: /tmp/research-out   # optional pinned writable dir
  env: [BRAVE_API_KEY]           # optional extra --env forwarding (rare)
---
<system prompt body — used verbatim as the agent's system prompt>
```

Rules:

- Unknown frontmatter keys are ignored by `runagent` (forward compatibility;
  pi-subagents already ignores most of them).
- `name` must match the filename stem (warn on mismatch).
- `tools:` — comma-separated. Built-in names pass through; `mcp:server/tool`
  entries are translated to `mcp__<server>__<tool>` (dashes/dots → underscores)
  for pi's `--tools` flag.
- `skills:` — names resolved in priority order:
  1. `.pi/skills/` (project, relative to cwd)
  2. `~/.pi/agent/skills/`
  3. `~/.agents/skills/`
  4. npm package skills (`~/.pi/agent/npm/node_modules/*/skills/*` and pi-package skill dirs)
  First match wins. Unresolved name → hard fail (exit 12).
- `extensions:` — names resolved against `~/.pi/agent/settings.json` `packages`:
  - `npm:<name>` → `~/.pi/agent/npm/node_modules/<name>` main entry
    (pi extension entry from package.json, else `index.ts`/`index.js`)
  - local path sources → as listed in settings.json
  - bare `<name>` matches `npm:<name>` first, then a local source whose path ends in `/name`
  Unresolved name → hard fail (exit 12).
- `mcp:` — server names must exist in `~/.pi/agent/mcp-adapter.json` → hard fail
  otherwise (exit 12).
- `sandbox:` — `on`/`off` or mapping (`workspace:`, `env:`). Default `on`.

### Seed profiles (v1)

1. **`web-researcher.md`** (extend existing file):
   ```yaml
   harness: pi
   model: dgx/qwen3.8-27b
   tools: read, write, edit, bash, fetch, mcp:brave-search/brave_web_search
   skills: []                     # (verify which skills exist; adjust)
   extensions: [pi-mcp-adapter, pi-web-access]
   mcp: [brave-search]
   sandbox: on
     workspace: /tmp/research-out
   ```
   (Decision, owner 2026-10-01: `write, edit` stay in the tools list — a sandboxed
   researcher needs write for its reports.)
2. **`full.md`** (new): `skills: [all]`, `extensions: [all]`, `tools: [all]`
   (→ no `--tools` flag, pi defaults + grep/find/ls), `mcp: [all]`, `sandbox: on`.
   This is "main-agent feature parity without copying state".

---

## 3. `runagent` CLI contract

```
runagent <agent_name> [options]

  -p, --prompt <text|@file|->   Task prompt. @file = read file, - = stdin.
                                With prompt → one-shot mode. Without → interactive.
  -m, --model <model>           Override profile model (provider/model)
  -w, --workspace <dir>         Override sandbox writable dir
  -c, --cwd <dir>               Working dir (default: $PWD)
  --harness <kind>              Override harness (v1: pi only)
  --env K=V                     Extra env var into sandbox (repeatable)
  --timeout <ms>                Wait timeout (default: 120000)
  --no-wait                     Fire-and-forget (submit prompt, don't wait)
  --keep / --no-keep            Keep herdr workspace (default: keep)
  --explain                     Print composed command, ask Proceed? [y/N]
  -h, --help
  runagent --list               Table: name, harness, model, sandbox, tools, mcp
```

Behavior:

- **Mode selection**: `-p` present → one-shot. `-p` absent + tty → launch and
  `herdr agent attach`. `-p` absent + non-tty → error "prompt required in
  non-interactive mode" (exit 2).
- **`--explain`**: prints the full composed launch (workspace, asb argv with all
  flags, generated mcp-config path) then `Proceed? [y/N]`; `n` → exit 0 no launch.
- **Defaults**: `cwd = $PWD`; `workspace = -w || profile.sandbox.workspace || cwd`.
  asb's $HOME edge case (private /tmp swap) is inherited automatically.
- **Stdout contract (agent-session safe)**: progress lines go to stderr; the final
  agent output (from `herdr agent read`) goes to stdout, prefixed by a single
  `=== Agent Output ===` line. Non-tty ⇒ never attaches, never prompts.
- **Exit codes**: `0` success (incl. `--explain` declined), `2` usage error,
  `10` launch failure (agent never registered), `11` wait timeout,
  `12` profile resolution failure (unknown skill/extension/mcp/model-format),
  `13` herdr server unavailable.
- **Side-effect files**: asb uses a **private tmpfs for /tmp** (host /tmp is NOT
  bind-mounted into the sandbox), so the system-prompt file and filtered MCP
  config live in `<workspace>/.runagent/` (the workspace is the bind-mounted
  writable dir); removed via `trap` on exit. `--explain` documents this side effect.

### Composed launch (pi harness)

```
asb pi <workspace> \
  --model <model> \
  --append-system-prompt <workspace>/.runagent/sysprompt.md   # file contents, from md body
  [--tools <list>]                # omitted for tools: [all]
  --no-skills --skill <path>...   # for explicit lists; omitted for [all]
  --no-extensions --extension <path>...   # same pattern; entries are FILES (dirs resolved to entry file)
  --mcp-config <workspace>/.runagent/mcp.json   # filtered; omitted for [all]
```

No positional args are passed to pi (pi treats bare positionals as chat
messages; asb already receives the workspace and the pane cwd is the workspace).
The system prompt is applied via `--append-system-prompt <path>` (pi reads the file
contents for that flag; `--system-prompt` takes literal text only), with the body
written to `<workspace>/.runagent/sysprompt.md`. Kept behind the one composer
function per this section.

---

## 4. Launch sequence (empirically verified 2026-10-01)

Verified end-to-end in this session with `asb pi` in a fresh herdr workspace
(detection, prompt, `--wait`, `done` status all confirmed; no herdr changes needed):

```
1. herdr status                      # ensure server; else `nohup herdr server &` (exit 13 on fail)
2. WS=$(herdr workspace create --label ra-<agent>-<suffix> --cwd <cwd> | jq -r .result.workspace.workspace_id)
3. PANE=$(herdr pane list --workspace $WS | jq -r '.result.panes[0].pane_id')
4. herdr pane run $PANE "asb pi <workspace> <args...>"
5. poll `herdr agent list` for entry with pane_id == PANE (≤30s; exit 10 on fail)
6. wait for agent_status == idle (≤30s)
7. wait for model ready (≤180s): agent_status reaches `idle` LONG before the model
   finishes loading; submitting a prompt during model load types text pi mangles
   into a spurious first turn. Ready signal = pi status bar with context-%
   (e.g. `0.0%/262k`) present and no `loading model` text, held stable across two
   consecutive polls (~3s apart), then a 2s settle. Warning + proceed on timeout.
8. herdr agent prompt $PANE "<prompt>" --wait --timeout <ms>     (exit 11 on timeout)
   [--no-wait: submit without --wait, skip 9]
9. herdr agent read $PANE --source recent --lines 200            # → stdout
10. finish: --no-keep → herdr workspace close $WS;
   else print "Workspace kept (ID: $WS). Close: herdr workspace close $WS / Attach: herdr agent attach $PANE"
```

Notes:

- Agents are identified by `pane_id` (this herdr version's agent list has no
  `name` field) — no stale-name collisions, no stale-agent removal needed.
- `herdr agent prompt --wait` alone matches `idle|done|blocked` (known gotcha:
  never use `--until` alone).
- The bwrap foreground process is mapped to the pi manifest by herdr detection
  (asb exports `HERDR_AGENT=pi` on the host side).

---

## 5. Security model

Layered, all fail-closed:

1. **System prompt** — profile body only; no main-agent context.
2. **Skills** — `--no-skills` + explicit `--skill` paths (or none).
3. **Extensions** — `--no-extensions` + explicit `--extension` paths (or none).
4. **Tools** — `--tools` allowlist incl. translated `mcp__server__tool` names.
5. **MCP** — generated filtered config (servers + their inline `env` keys);
   empty config when no `mcp:` key.
6. **ASB sandbox** (default on) — workspace = only general writable path;
   `/tmp` is a **private tmpfs** (not a host bind mount); system dirs ro; `/etc` per-file;
   env cleared (only HOME/PATH/TERM/LANG/HERDR_*/`--env`);
   shadow/sudoers invisible; herdr socket rw (same-uid parity).
   runagent's side-effect files (sysprompt.md, mcp.json) therefore live in
   `<workspace>/.runagent/`, cleaned by the EXIT trap.
   **v1 limits**: single writable dir, no network isolation, agent state dirs rw.

`--explain` is the trust/audit tool: the exact composed command is always inspectable.

---

## 6. File layout

```
~/.pi/agent/skills/herdr-cli/
├── SKILL.md                          # + section "Named agent profiles (runagent)"
└── scripts/
    ├── runagent                      # bash entry (new)
    ├── agent_profile.py              # python: parse/resolve/compose (new)
    ├── herdr-common.sh               # (unchanged; runagent may reuse herdr_ensure_server)
    └── run-*-herdr.sh                # (unchanged; ad-hoc model-only launches)

~/.local/bin/runagent                 # symlink → skill script
~/.pi/agent/agents/
├── web-researcher.md                 # extended with new keys
└── full.md                           # new
```

---

## 7. Implementation plan

### Phase 1 — `agent_profile.py` (core, testable in isolation)
1. Frontmatter parser (python3 stdlib only — small YAML-subset parser for
   `key: value`, `key: [a, b]`, and the nested `sandbox:` mapping; no pyyaml
   dependency. If the subset proves fragile, vendor a 50-line parser or allow
   `pip show pyyaml` and use it if present — decide by what the real files need).
2. Profile loader: `load(name, cwd)` → dict; validate name/filename match;
   `--list` renderer.
3. Resolvers (each returns concrete values or raises `ProfileError`):
   - `resolve_skills(names, cwd)` → paths
   - `resolve_extensions(names)` → paths (settings.json packages scan)
   - `resolve_mcp(names)` → filtered config dict + temp-file writer
   - `translate_tools(tools)` → pi `--tools` string
4. Composer: `compose_launch(profile, overrides)` → `(asb_argv, meta)` where meta
   carries workspace/mcp-config-path/cwd. Pure function — unit-testable.
5. CLI: `agent_profile.py compose <agent> [--model …] [--workspace …] [--explain-json]`
   prints the composed argv as JSON (used by the bash wrapper and tests).

**Milestone M1**: `python3 agent_profile.py compose web-researcher` prints a
correct, complete asb argv for a real profile.

### Phase 2 — `runagent` bash wrapper
1. Arg parsing (mirror §3), tty detection, prompt sources (text/@file/stdin).
2. Call `agent_profile.py compose` → JSON argv.
3. `--explain`: pretty-print + `read -p "Proceed? [y/N]"`.
4. Launch sequence §4 (herdr ensure/create/pane-run/poll/prompt/read/finish).
   Reuse `herdr_ensure_server` from herdr-common.sh where sensible.
5. Exit codes §3; temp-file trap; stderr progress / stdout output split.
6. `--list` passthrough.
7. `ln -s` into `~/.local/bin`.

**Milestone M2**: `runagent --list` and `runagent web-researcher --explain`
work from a bare shell.

### Phase 3 — End-to-end
1. Extend `web-researcher.md` + create `full.md` (§2 seeds).
2. `runagent web-researcher -p "Find the release date of pi 0.99 and cite sources" -w /tmp/research-e2e`
   → verify: sandboxed (check bwrap cmdline via pane process-info), only allowed
   tools present (ask agent to list its tools), brave-search works, output lands
   in /tmp/research-e2e, nothing written outside.
3. `runagent full -p "list your tools"` → verify full surface.
4. Non-interactive: `runagent web-researcher -p "say OK" | head` in a pipe →
   clean stdout, correct exit code.
5. `--no-wait`, `--no-keep`, `-m` override, `-w` override, `--explain n` paths.
6. Failure paths: unknown skill name → exit 12; herdr down → exit 13; timeout → 11.

**Milestone M3**: all e2e checks pass; negative tests exit with documented codes.

### Phase 4 — Docs
1. `SKILL.md` section: "Named agent profiles (`runagent`)" — when to use
   (named role → `runagent`; ad-hoc model → `run-*-herdr.sh`), profile format
   reference, `--explain` as the audit step, exit codes.
2. Note in SKILL.md that the raw `run-*-herdr.sh` scripts remain for
   profile-less launches.

**Milestone M4**: docs merged; a fresh agent session reading only SKILL.md can
launch a profiled agent correctly.

### Phase 5 — Watch items (do NOT block v1)
- **`--no-extensions` × herdr detection**: test that a profile with explicit
  extension lists still gets detected/tracked by herdr (the state-reporting hook
  is an extension). If detection degrades, introduce the smallest possible
  auto-included infra list (first member: the herdr integration extension).
- Extension main-entry resolution for npm packages (package.json pi-entry
  variants) — handle whatever the 5–6 installed packages actually declare.
- asb v2: multiple writable dirs (TODO in vault inbox) + network egress proxy.
- claude/opencode harness translation (schema is ready; mapping is a future PR).

---

## 8. Test plan (acceptance criteria)

| # | Test | Pass when |
|---|------|-----------|
| T1 | `runagent --list` | table renders, exit 0 |
| T2 | `runagent web-researcher --explain` → `n` | composed command printed, no launch, exit 0 |
| T3 | `runagent web-researcher -p "..." -w /tmp/ra-test` | one-shot completes; output on stdout; exit 0 |
| T4 | sandbox verification | bwrap cmdline shows `--bind <workspace>` as only general writable; agent cannot write outside (attempt + verify) |
| T5 | tool surface | agent's tool list matches profile `tools:` (+ translated mcp tools), no extras |
| T6 | skill/extension isolation | agent has no skills/extensions beyond allowlist (ask it to enumerate) |
| T7 | MCP isolation | only allowlisted servers' tools callable; brave-search search succeeds |
| T8 | `full` profile | full tool/skill/extension/MCP surface, sandbox still on |
| T9 | non-tty pipe | `runagent … -p "say OK" \| cat` clean stdout, exit 0; no prompt → exit 2 |
| T10 | overrides | `-m`, `-w`, `-c` each take effect in composed command |
| T11 | `--no-wait` | returns after submit, workspace kept |
| T12 | `--no-keep` | workspace closed on finish |
| T13 | failures | unknown skill → 12; herdr stopped → 13; tiny timeout → 11; bad agent name → 2 |
| T14 | interactive (manual) | `runagent web-researcher` on a tty attaches to TUI |

---

## 9. Risks & mitigations

| Risk | Mitigation |
|------|-----------|
| YAML-subset frontmatter parser fragility | Real files are the test suite; fall back to pyyaml-if-present with clear error if absent |
| npm extension main-entry variety | Resolve against the 5–6 actually-installed packages; hard-fail with the expected locations listed |
| `--no-extensions` breaks herdr state reporting | Phase 5 watch item; detection has screen-based fallback; smallest infra list if needed |
| Long `--system-prompt` inline | One composer function; temp-file fallback if pi rejects |
| herdr agent-list schema drift (no `name` field) | Wrapper keys off `pane_id` only; document schema assumption |
| asb single-writable-dir limit | Accepted for v1; vault TODO for asb v2; `sandbox: off` escape hatch |

---

## 10. Out of scope (v1)

- claude/opencode/codex harness translation (schema-ready, deferred)
- network egress isolation (asb v2)
- multiple writable dirs (asb v2)
- workspace auto-GC (`runagent --gc` later if needed)
- pi-native `subagent` tool integration with profiles (deprecated path)
- hardcoded infra extension list (only if watch item forces it)
