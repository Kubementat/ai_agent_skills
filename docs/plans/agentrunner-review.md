# `runagent` Implementation Review

**Date:** 2026-10-01
**Reviewed against:** `docs/plans/agentrunner-spec.md` (approved spec)
**Scope:** `~/.pi/agent/skills/herdr-cli/scripts/{agent_profile.py, runagent}`, `SKILL.md`, `~/.pi/agent/agents/{web-researcher.md, full.md}`, `~/.local/bin/runagent` symlink.
**Method:** read-only review + non-launching tests (`--list`, `--explain` (non-tty), exit-code failure paths). No sandboxed agents were launched.

## Verdict: **REJECT** (2 blockers — both small, localized fixes; re-review after fix)

The CLI contract, fail-closed allowlist composition, launch-sequence structure, and exit-code
plumbing are substantially correct. However, the composed pi command has **two bugs that break the
core purpose**: the profile's system prompt is never applied (a file *path* is passed to
`--system-prompt`, which takes literal text), and the workspace path is passed as a bare pi
positional, which pi interprets as a **chat message** (spurious first turn on every launch).
Acceptance tests T3–T8 cannot pass as-is.

---

## Findings

| # | Severity | File:Line | Description | Suggested fix |
|---|----------|-----------|-------------|---------------|
| 1 | **blocker** | `scripts/agent_profile.py:429` | `pi_argv += ["--system-prompt", str(sp_path)]` — pi's `--system-prompt <text>` takes literal text (verified via `pi --help`). The agent's system prompt becomes the string `/…/.runagent/sysprompt.md`; the profile body is never used. | Use the spec's sanctioned fallback: `--append-system-prompt <sp_path>` (pi help: "Append text **or file contents**"). Verify whether `--system-prompt ""` suppresses the default coding-assistant prompt; if not, accept the default+append composition or find pi's blanking mechanism. Keep behind the one composer function per spec §3. |
| 2 | **blocker** | `scripts/agent_profile.py:427` | `pi_argv = ["pi", ws]` — pi usage is `pi [options] [@files...] [messages...]`; a bare positional is a **message**. Every launch sends the workspace path as a spurious first user turn. asb already receives `ws` as its workspace arg and the pane cwd is the workspace, so the positional is both wrong and redundant. | `pi_argv = ["pi"]` (drop `ws`). |
| 3 | **major** | `scripts/runagent:123` | Bad agent name exits **12**, but spec §8 T13 requires **exit 2** for "bad agent name". (The §3 exit-code table is silent on this case; the test plan is the acceptance criterion.) | In the wrapper, pre-check profile existence (or map python's "unknown agent profile" error to exit 2) so only skill/extension/mcp resolution failures yield 12. |
| 4 | **major** | `scripts/agent_profile.py` (`_extension_entries_from_package`) | web-researcher composes `--extension /home/…/npm/node_modules/pi-web-access/dist` — a **directory**. pi's `--extension` "Load an extension file"; directory paths may be rejected at launch. Unverified (no launch performed). | Resolve directories to their entry file (`dist/index.js`) in `_extension_entries_from_package`; verify with a launch after fixing #1/#2. |
| 5 | **major** | `~/.pi/agent/skills/herdr-cli/SKILL.md` | Spec §6 / Phase 4 required a "Named agent profiles (runagent)" section. **It does not exist** — zero matches for `runagent` in SKILL.md (194 lines). Milestone M4 not met. | Add the section: when to use (profile → `runagent`; ad-hoc → `run-*-herdr.sh`), profile format reference, `--explain` audit step, exit codes. |
| 6 | **major** | repo git state | Spec doc was to be committed: `docs/plans/agentrunner-spec.md` is **untracked** (`??`). Also untracked: `skills/herdr-cli/scripts/runagent`, `skills/herdr-cli/scripts/agent_profile.py` (the `~/.pi` path is a symlink into this repo, so the implementation lives here and is uncommitted). | `git add` spec doc + both scripts (and the SKILL.md section once written); commit. |
| 7 | **major** | `~/.pi/agent/agents/web-researcher.md` (frontmatter) | `tools: read, write, edit, bash, fetch, mcp:…` — spec §2 seed allowlist is `read, bash, fetch, mcp:…`. `write`/`edit` widen the surface beyond the locked design (only `skills:` was marked "verify/adjust"). Confirm intentional or restore the spec list. | Decide; if intentional, amend spec §2 seed; else remove `write, edit`. |

### Minor

| # | Severity | File:Line | Description | Suggested fix |
|---|----------|-----------|-------------|---------------|
| 8 | minor | `scripts/runagent:272` | `echo ""` writes a blank line to **stdout** before `=== Agent Output ===`; spec §3 stdout contract is the marker line then output (agent-session pipeable). | Drop it or send to stderr. |
| 9 | minor | `scripts/agent_profile.py` (`compose_launch`) | `--explain` has side effects before the user decides: creates the workspace dir and writes `.runagent/{sysprompt.md, mcp.json}` (removed again by the EXIT trap). | Acceptable, but document; optionally defer file writes to post-approval. |
| 10 | minor | `scripts/runagent` (interactive branch) | Interactive attach path always prints "Workspace kept" and ignores `--no-keep`. | Honor `KEEP` in the interactive branch. |
| 11 | minor | `scripts/agent_profile.py` (`write_mcp_config`); `scripts/runagent` (`ARGV_JSON`) | Dead code: `write_mcp_config` (the spec's mktemp approach) is unused; `ARGV_JSON` is parsed but never used. | Remove. |
| 12 | minor | `scripts/runagent` (`wait_for_ready`) | Up to ~180 s extra model-ready wait not in spec §4. Reasonable hardening (screen-scrape is fragile); undocumented. | Add to spec §4 as a verified step. |
| 13 | minor | `scripts/runagent` | `--timeout` not validated as numeric; garbage flows into `herdr agent prompt --timeout`. | Validate with a regex, die 2. |
| 14 | minor | `scripts/runagent` (`herdr_ensure_server`) | Inlined rather than reusing `herdr_ensure_server` from `herdr-common.sh` (spec: "where sensible"). | Optional; source herdr-common.sh. |

### Nits

| # | Severity | File:Line | Description |
|---|----------|-----------|-------------|
| 15 | nit | `scripts/runagent` | `set -uo pipefail` (no `-e`) — consistent with the explicit-RC-check style used throughout; fine, just note it. |
| 16 | nit | `scripts/agent_profile.py` (`cmd_list`) | TOOLS column truncates at 40 chars (`mcp:brav…`); MCP at 24. |
| 17 | nit | `scripts/runagent` (`die`) | `die`'s optional exit-code argument is never used with a non-2 code. |

### Justified deviation (no action on code; update spec)

- **Temp-file location**: spec §3 says filtered MCP config → `mktemp` in host `/tmp` + `trap`,
  claiming host /tmp is bind-mounted into the sandbox. **asb's source shows /tmp is a *private
  tmpfs*** (only the workspace is generally writable; `$HOME` → private /tmp). The implementation's
  choice to place `sysprompt.md` + `mcp.json` in `<workspace>/.runagent/` (removed by the EXIT
  trap) is **correct and necessary**. Update spec §3/§5 to match reality.

---

## Security check (composition level, via `--explain`)

`runagent web-researcher --explain` composes:

```
asb pi /tmp/research-out /tmp/research-out --model dgx/qwen3.8-27b \
  --system-prompt /tmp/research-out/.runagent/sysprompt.md \
  --tools read,write,edit,bash,fetch,mcp__brave_search__brave_web_search \
  --no-skills --no-extensions \
  --extension ~/.pi/agent/npm/node_modules/pi-mcp-adapter/index.ts \
  --extension ~/.pi/agent/npm/node_modules/pi-web-access/dist \
  --mcp-config /tmp/research-out/.runagent/mcp.json
```

| Check | Result |
|-------|--------|
| `--no-skills` present for empty `skills: []` (fail-closed, none inherited) | ✅ |
| `--no-extensions` + explicit `--extension` paths | ✅ (dir-path caveat, finding #4) |
| `--mcp-config` filtered config; `/tmp/research-out/.runagent/mcp.json` contains **only** `brave-search` incl. its inline `env` block | ✅ |
| `--tools` allowlist with `mcp:brave-search/brave_web_search` → `mcp__brave_search__brave_web_search` translation | ✅ |
| No main-agent state leakage in flags (no inherited skills/ext/mcp) | ✅ |
| `full` profile: no `--tools`, no `--no-skills`, no `--no-extensions`, no `--mcp-config` (all = global/auto surface), sandbox on | ✅ |
| System prompt isolation (body only) | ❌ broken by finding #1 (prompt never applied) |
| No spurious prompt injection at launch | ❌ broken by finding #2 (workspace path sent as message) |

## Test results (non-launching subset of §8)

| Test | Result | Evidence |
|------|--------|----------|
| T1 `runagent --list` | **PASS** | Table rendered (14 profiles), exit 0. |
| T2 `--explain` → decline | **PASS (non-tty variant)** | Composed command printed, "non-tty: not launching", exit 0, no workspace created in herdr. Interactive `n` prompt path not testable non-tty; auto-decline on non-tty is consistent with §14/T9. |
| T10 overrides via `--explain` | **PASS** | `-m evo/test-model -w /tmp/ra-review-ws -c /home` all appear in model/workspace/cwd and composed command. |
| T13 bad agent name | **FAIL (spec)** | `runagent nosuchagent --explain` → exit **12**; spec T13 requires **2** (finding #3). |
| T13 unknown skill → 12 | **PASS** | `resolve_skills(['definitely-not-a-skill'])` raises `ProfileError` ("unknown skill … searched: …"), which maps to exit 12 via `main()`. (No existing profile references an unknown skill; verified via module import, no files modified.) |
| T13 herdr stopped → 13 | **SKIPPED** | herdr server is running; stopping it is destructive and out of the allowed read-only scope. Code path reviewed: `herdr_ensure_server` → nohup start → recheck → `exit 13`, matches spec §4. |
| T9 non-tty, no prompt | **PASS** | `runagent web-researcher < /dev/null` → "prompt required in non-interactive mode (no tty)", exit 2. |
| `--harness claude` | **PASS** | "harness 'claude' not supported (only pi supported in v1)", exit 2 (spec §3/#9). |
| T3–T8, T11, T12, T14 | **SKIPPED** | Require launching sandboxed agents (out of review scope). **Cannot pass currently** due to blockers #1/#2. |

## Process gaps

- `docs/plans/agentrunner-spec.md` **not committed** (untracked) — finding #6.
- `full.md` **exists** and matches the spec seed (absent `tools:` ≡ `[all]` → no `--tools` flag; `skills/extensions/mcp: [all]`; `sandbox: on`). ✅
- `web-researcher.md` extended with all new keys; tools-list deviation — finding #7.
- `~/.local/bin/runagent` symlink present → `~/.pi/agent/skills/herdr-cli/scripts/runagent` (which is the repo path via a directory symlink). ✅
- SKILL.md section **missing** — finding #5.

## Prioritized fix list

1. **(blocker)** `agent_profile.py:429` — replace `--system-prompt <path>` with `--append-system-prompt <path>` (verify default-prompt suppression).
2. **(blocker)** `agent_profile.py:427` — drop the `ws` positional from pi's argv (`pi_argv = ["pi"]`).
3. **(major)** Map "unknown agent profile" to exit 2 in the wrapper (T13); keep 12 for skill/extension/mcp resolution.
4. **(major)** Resolve extension dirs to entry files (`pi-web-access/dist` → `dist/index.js`); verify with a launch.
5. **(major)** Add the "Named agent profiles (runagent)" section to `SKILL.md`.
6. **(major)** Commit `docs/plans/agentrunner-spec.md` + `skills/herdr-cli/scripts/{runagent, agent_profile.py}` (+ SKILL.md).
7. **(major)** Decide web-researcher `write, edit` tools (spec deviation).
8. **(minor)** Fix stdout blank line; honor `--no-keep` interactively; remove dead code; validate `--timeout`; document `wait_for_ready` in spec §4; correct spec §3/§5 /tmp claim.
9. After 1–4: re-run full acceptance T3–T14 (launching) before merging.
