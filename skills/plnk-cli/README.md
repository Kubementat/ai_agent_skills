# plnk-cli — skill

Agent skill for driving [Planka](https://planka.app) kanban project management through the
[`plnk`](https://github.com/plattnum/planka-cli) CLI: projects → boards → lists → cards →
tasks/comments/attachments, plus labels, custom fields, memberships, and users.

CLI-first by design: `plnk` is the only interface. The skill defines no shadow API over the REST
endpoints and assumes no fixed kanban columns.

## Files

| Path | Origin | Purpose |
|---|---|---|
| `SKILL.md` | upstream, adjusted | Entrypoint: invariants, scoping rules, operating procedure |
| `references/commands.md` | upstream, verbatim | Every command, flag, alias; intent→command table; resolution playbooks |
| `references/api-quirks.md` | upstream, verbatim | Planka API behaviors that change how the CLI must be used |
| `references/grammar.md` | vendored from `docs/cli/grammar.md` | Grammar, scoping, output formats, JSON envelopes, exit codes, `@file` input |
| `references/custom-fields.md` | vendored from `docs/cli/custom-fields.md` | Field-group / field / card-field-value model, template adoption, value rules |
| `references/examples.md` | vendored from `docs/cli/examples.md` | Worked end-to-end examples incl. exit-code branching |
| `references/auth-and-transport.md` | condensed from `docs/cli/auth.md` + `docs/cli/transport.md` | Credential precedence, token setup, retries, rate limits |
| `LICENSE.upstream` | upstream, verbatim | MIT license of the vendored content |

Everything an agent needs is on disk — no reference requires network access.

### What was deliberately not copied

Upstream also ships 15 per-resource docs (`docs/cli/projects.md`, `boards.md`, `lists.md`,
`cards.md`, `tasks.md`, `comments.md`, `labels.md`, `attachments.md`, `memberships.md`,
`users.md`, …). Their command syntax is already covered by `references/commands.md`, so they were
left out to keep the skill's context footprint small. The five docs above were kept because they
carry content `commands.md` does not: canonical grammar and exit codes, the custom-field model,
worked examples, and auth/transport tuning.

## Prerequisite: the `plnk` binary

The skill is inert without the binary, which is **not** part of this repo.

```bash
# verified manual install (Linux x86_64 example)
REL=https://github.com/plattnum/planka-cli/releases/download/v0.3.0
curl -sL -O $REL/plnk-cli-x86_64-unknown-linux-gnu.tar.gz
curl -sL -O $REL/plnk-cli-x86_64-unknown-linux-gnu.tar.gz.sha256
sha256sum -c plnk-cli-x86_64-unknown-linux-gnu.tar.gz.sha256
tar xzf plnk-cli-x86_64-unknown-linux-gnu.tar.gz
install -m 0755 plnk-cli-x86_64-unknown-linux-gnu/plnk ~/.local/bin/plnk
plnk --version
```

Upstream also publishes `plnk-cli-installer.sh` per release, and `cargo install --git
https://github.com/plattnum/planka-cli plnk-cli` works (Rust 1.87+). The shell installer defaults
to `~/.cargo/bin` and edits your shell profile; the manual route avoids both.

## Prerequisite: credentials

```bash
plnk init                      # interactive; writes ~/.config/plnk/config.toml (0600)
plnk auth status && plnk project list
```

Or stateless via `PLANKA_SERVER` + `PLANKA_TOKEN`. Create a token in the Planka web UI under
*Profile → Settings → Tokens*. Full detail:
[references/auth-and-transport.md](references/auth-and-transport.md).

No server URL, token, or hostname belongs in this skill — the repository's `origin` is public on
GitHub. Keep instance details in `~/.config/plnk/config.toml` or your own environment.

## Install this skill

From the repository root, use the collection installer (symlink by default):

```bash
./install-skill.sh --list                            # confirms plnk-cli is discovered
./install-skill.sh --agent pi --skill plnk-cli       # into the current project dir
./install-skill.sh --agent claude --global --skill plnk-cli
./install-skill.sh --interactive                     # guided wizard
./install-skill.sh --agent pi --skill plnk-cli --dry-run
```

Or link it by hand for pi:

```bash
mkdir -p ~/.pi/agent/skills
ln -sf "$(pwd)/skills/plnk-cli" ~/.pi/agent/skills/plnk-cli
```

## Adjustments made to upstream

So future re-syncs aren't mistaken for accidental drift:

1. **`SKILL.md` References section** rewritten — upstream pointed at `../../docs/cli/*.md`, paths
   that do not exist outside the upstream checkout. Now points at the vendored files above, with a
   "never fetch from the network" note.
2. **`SKILL.md` config path corrected** — upstream said `~/.config/planka/config.toml`. Current
   `plnk` uses `~/.config/plnk/config.toml` (honors `XDG_CONFIG_HOME`, overridable with
   `PLANKA_CONFIG`); `planka/` survives only as a read-once legacy migration path.
3. **`SKILL.md` Prerequisites section added** — binary + auth pre-flight check, and an explicit
   "do not fall back to raw `curl`" rule.
4. **`references/examples.md`** — its one link to `../../README.md` retargeted to `grammar.md`.
5. **`README.md`** replaced — upstream version documented the author's local paths and
   `pi install git:…` packaging, which does not apply here.
6. **`LICENSE.upstream`** added, since MIT-licensed text is redistributed.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/plattnum/planka-cli |
| Synced from commit | `78944eaed2ad2923819f3588aaf73435378d6671` (2026-08-10) |
| Binary release pinned to | v0.3.0 |
| License | MIT, Copyright (c) 2026 plattnum — see `LICENSE.upstream` |
| Synced | 2026-08-31 |

Re-sync by re-cloning upstream, re-copying the files listed above, and re-applying adjustments 1–5.
Check `CHANGELOG.md` upstream for renames (`planka/` → `plnk/` config and the `PLANKA_*` →
`PLNK_TUI_*` env split both landed around 0.3.0).
