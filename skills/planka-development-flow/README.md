# planka-development-flow

A ticket pipeline where **Planka is the system of record** and **AI agents are workers**.

You write tickets on a Planka board. A classical bash script (`dispatch.sh`)
polls the board, claims tickets, spins up git worktrees, launches implementer
and reviewer agents (via [herdr](#required-skills)), verifies their work with
hard gates, and cleans up after merged work. The agents do only fuzzy work —
implementing code and reviewing diffs. Everything deterministic (claiming,
gates, reporting, cleanup) lives in the script.

```
You:       Inbox ──► Ready           (write ticket, you decide what gets worked)
dispatch:  Ready ──► Claimed ──► In Progress ──► (implementer agent works)
gates:     G1 commits · G2 tests · G3 protected files · G4 state + report
dispatch:  ──► Ready for Review ──► In AI Review ──► (reviewer agent works)
AI review: APPROVE ──► Human Review      CHANGES ──► Ready (re-implement reads review)
You:       Human Review ──► Done (merge branch)  |  Rejected
dispatch:  (next run) cleans worktrees + branches of Done cards
```

## Core design rule

**Deterministic work in the script, fuzzy work in agents.**

The agent's self-report is never trusted. The dispatcher re-runs the test
command itself, re-counts commits, diffs the branch itself, and auto-captures
the agent's final transcript if the agent forgot to post a report. Agents get
exactly **one** `plnk` mutation each: the card move. See
[references/lessons.md](references/lessons.md) for the evidence behind these
rules — they were learned from failed test runs, not theory.

## Directory layout

```
planka-development-flow/
├── SKILL.md                      # agent-facing skill summary
├── README.md                     # this file
├── config/
│   └── config.env.example        # config template
├── references/
│   ├── board-map.md              # required Planka board structure + ID lookup
│   ├── card-format.md            # ticket description contract
│   ├── gates.md                  # phases, gate chain, bounce/reject detail
│   └── lessons.md                # why the architecture is shaped this way
├── profiles/
│   ├── impl.md                   # runagent profile for the implementer agent
│   └── review.md                 # runagent profile for the reviewer agent
└── scripts/
    ├── setup-board.sh            # one-time board bootstrap (idempotent)
    ├── setup-agents.sh           # install runagent profiles to ~/.pi/agent/agents/ (idempotent)
    ├── dispatch.sh               # the orchestrator (run / implement / review / cleanup / status)
    ├── new-card.sh               # create + provision a ticket
    └── prompts/
        ├── implementer.txt       # implementer agent prompt
        └── reviewer.txt          # reviewer agent prompt
```

## Required skills

This skill depends on two sibling skills (both in this repo):

| Skill | What it provides |
|---|---|
| [`plnk-cli`](../plnk-cli/) | Install + authentication of the `plnk` CLI — the Planka API client. `setup-board.sh` and `dispatch.sh` are built on it. Get it: `plnk auth login --server <url> --email ... --password ...`, verify with `plnk auth whoami`. |
| [`herdr-cli`](../herdr-cli/) | The `herdr` terminal workspace manager and its `scripts/run-pi-herdr.sh` launcher. The dispatcher launches every implementer/reviewer session through it. The launcher path is the `HERDR_RUN` config variable. |

Plus plain system tools: `git`, `jq`, `flock`.

## Setup (first time only)

1. **Install + authenticate `plnk`** (see the `plnk-cli` skill):

   ```bash
   plnk auth login --server <your-planka-url> --email ... --password ...
   plnk auth whoami    # must succeed
   ```

2. **Start a herdr server** (see the `herdr-cli` skill):

   ```bash
   nohup herdr server > /tmp/herdr-server.log 2>&1 &
   herdr status
   ```

3. **Create the board.** One command — idempotent, safe to re-run:

   ```bash
   scripts/setup-board.sh
   # options: --project NAME (default AI-Orchestration)
   #          --board NAME   (default "Dispatch Board")
   #          --config PATH  (default ~/.config/planka-development-flow/config.env)
   ```

   It creates the project, board, the 9 lists and the `Dispatch` custom field
   group (with `project` and `attempts` fields) if missing, and writes a
   `config.env` with all Planka IDs already filled in. It never overwrites an
   existing config. The board must have exactly the structure described in
   [references/board-map.md](references/board-map.md) — the dispatcher assumes
   the exact list names.

4. **Edit the config** at `~/.config/planka-development-flow/config.env`
   (bash-sourced, no parser; template: `config/config.env.example`):

   - set `MODEL` (your herdr/pi model, e.g. `<provider>/<model>`) and `HERDR_RUN`
     (path to `herdr-cli`'s `run-pi-herdr.sh`) — the script refuses to run
     without `HERDR_RUN` and without a resolvable model;
   - `RUNNER` selects how agent sessions are launched (default `herdr`, the
     legacy `run-pi-herdr.sh` path). `RUNNER=runagent` launches agents through
     `runagent` + the asb bubblewrap sandbox instead; then set `RUNAGENT`
     (command name or absolute path) and optionally `AGENT_IMPL` / `AGENT_REVIEW`
     (runagent profile names, default `impl` / `review` — install the bundled
     profiles with `scripts/setup-agents.sh`);
   - optionally set `MODEL_IMPL` / `MODEL_REVIEW` to use different models for
     the implementer and reviewer agents (each falls back to `MODEL`), and
     `THINKING_IMPL` / `THINKING_REVIEW` to set each agent's pi thinking level
     (`off/minimal/low/medium/high/xhigh/max` — appended as a `:level` suffix,
     e.g. `provider/model:high`; an explicit suffix on the model wins);
   - add one `PROJ_<name>_*` block per repo you want to dispatch to:

   ```bash
   # key = project field value with non-alphanumerics -> _  (my-app -> my_app)
   PROJ_my_app_repo=$HOME/my-app
   PROJ_my_app_base_ref=main          # worktrees always branch from here, never HEAD
   PROJ_my_app_test=npm test          # gate G2 — dispatcher re-runs this itself
   PROJ_my_app_hard=".env* *.pem keys/* secrets/*"   # touching any -> bounce
   PROJ_my_app_soft="Dockerfile docker-compose.yml package.json package-lock.json"
   ```

5. **Verify:**

   ```bash
   scripts/dispatch.sh status   # prints a board overview per list
   ```

## Config reference

`~/.config/planka-development-flow/config.env` (override location with the
`PLANKA_DEVFLOW_CONFIG` env var).

| Key | Meaning |
|---|---|
| `PLANKA_PROJECT` / `PLANKA_BOARD` | board IDs (filled by setup-board.sh) |
| `LIST_*` | IDs of the 9 lists, in flow order |
| `FIELD_GROUP` / `BASE_GROUP` / `FIELD_PROJECT` / `FIELD_ATTEMPTS` | custom field IDs |
| `MAX_PARALLEL` | tickets in flight per dispatch run (default 2) |
| `MAX_ATTEMPTS` | gate bounces allowed before `Rejected` (default 3) |
| `CARD_TIMEOUT` | seconds to wait for one agent (default 3600) |
| `POLL_INTERVAL` | seconds between card-state polls (default 20) |
| `MODEL` | herdr/pi model default for implementer + reviewer (required unless the role override is set) |
| `MODEL_IMPL` / `MODEL_REVIEW` | per-role model overrides, fall back to `MODEL` |
| `THINKING_IMPL` / `THINKING_REVIEW` | pi thinking level per role, appended as `:level` suffix (default unset) |
| `HERDR_RUN` | path to `run-pi-herdr.sh` (required, must be executable) |
| `CARD_TIMEOUT_MS` | herdr-side timeout in ms (default 1800000) |
| `WT_ROOT` | worktree root; worktrees live at `<root>/<project>/<cardId>` |
| `PROJ_<key>_repo` | absolute repo path; `key` = card `project` field with non-alphanumerics → `_` |
| `PROJ_<key>_base_ref` | branch to create `ai/<cardId>` from (never HEAD) |
| `PROJ_<key>_test` | test command, run by the **dispatcher** in the worktree (gate G2) |
| `PROJ_<key>_hard` | space-separated globs — touching any → bounce (gate G3 hard) |
| `PROJ_<key>_soft` | space-separated globs — touching any → flag comment, continues (gate G3 soft) |

The `project` field value on a card is the machine link to the repo config:
`my-app` → key `PROJ_my_app_*`. Cards whose project isn't in the config are
**skipped, not bounced**.

## Writing tickets

1. Write the description as markdown following the contract in
   [references/card-format.md](references/card-format.md):

   ```markdown
   ## Goal
   One or two sentences: what to achieve, in plain language.

   ## Repo
   <absolute repo path — must match the project field's config entry>

   ## Context
   Background the agent cannot discover: relevant files, prior decisions,
   gotchas, related tickets.

   ## Acceptance criteria
   - [ ] verifiable statement
   - [ ] verifiable statement

   ## Constraints
   - Do not touch X / Y (mirror the config's protected patterns)
   - Keep the change minimal
   ```

   Rules: acceptance criteria must be **individually verifiable** (the
   reviewer checks each one and reports met/not met); constraints are
   **absolute** for the implementer and enforced by the reviewer.

2. Create the card:

   ```bash
   scripts/new-card.sh --title "Add /foo" --project my-app \
                       --desc /tmp/ticket.md [--list inbox|ready]
   ```

   This creates the card, adopts the `Dispatch` field group onto it, and sets
   the `project` field. It rejects unknown project names up front.

3. **Cards in `Ready` are the gate** — only cards you (or your process) move
   to `Ready` get worked. `Inbox` is your staging area.

## The workflow end-to-end

### 1. You create and prioritize

Write tickets (above), stage them in `Inbox`, and move the ones you want
worked now to `Ready`. This is the only human gating point in the pipeline:
no ticket enters an agent unless it is in `Ready` with a known project and
`attempts < MAX_ATTEMPTS`.

### 2. Dispatch run (implement phase)

`dispatch.sh run` does a full pass in three phases: implement → review →
cleanup. Phases can also run individually. For each eligible `Ready` card
(up to `MAX_PARALLEL` at a time, in parallel):

1. **Claim** — `Ready → Claimed → In Progress`. The move is the lock: a card
   leaves `Ready` before the agent starts, so a concurrent/cron-overlapping
   run cannot claim it. A `flock` lockfile makes overlapping runs no-ops anyway.
2. **Worktree** — `<WT_ROOT>/<project>/<cardId>` on branch `ai/<cardId>`,
   created from `base_ref` (reused on re-dispatch after a bounce).
3. **Launch** — the implementer agent via `run-pi-herdr.sh --no-wait` with the
   substituted prompt from `scripts/prompts/implementer.txt`.
4. **Wait** — the dispatcher polls `plnk card get` every `POLL_INTERVAL`
   seconds; the card's list is the progress signal, not the agent's transcript.
   If the agent **ends its turn without moving the card** (idle), the
   dispatcher rescues after a 120 s grace: it reads the transcript and
   completes the move from deterministic evidence — a `STATUS: FAILED` marker
   → `Ready`; ≥1 commit on the branch → `Ready for Review`; otherwise →
   `Ready`. The gates still apply either way.
5. **Gates** (the agent's claims are input, not evidence):

   | Gate | Check (run by the dispatcher) | Failure |
   |---|---|---|
   | G1 | ≥ 1 commit on `ai/<cardId>` vs `base_ref` | bounce |
   | G2 | `PROJ_<key>_test` passes in the worktree (output tail posted) | bounce |
   | G3 hard | no changed file matches `*_hard` globs | bounce |
   | G3 soft | changed files match `*_soft` globs | flag comment, **continues** |
   | G4 | card is in `Ready for Review` (agent moved it) | bounce |

   If the card ended back in `Ready` (agent self-reported failure), it bounces
   without gates.
6. **Report** — agents never post reports reliably, so the dispatcher checks
   the comment count and auto-captures the agent's final transcript from herdr
   as `## Report (auto-captured by dispatcher …)` when missing.
7. **Close** — the agent's herdr workspace is closed.

**Bounce vs reject:** on gate failure the `attempts` field increments. Below
`MAX_ATTEMPTS` the card returns to `Ready` — the re-implementer reuses the
same worktree/branch and reads the gate/review comments to fix exactly what
failed. At `MAX_ATTEMPTS` the card goes to `Rejected`.

### 3. AI review phase

Same claim/launch/wait machinery, on `Ready for Review` cards:
`Ready for Review → In AI Review` → reviewer agent (read-only for code; its
only mutation is the card move) → its verdict is auto-captured if not posted:

- `APPROVE` → `Human Review`
- `CHANGES REQUESTED` → `Ready` — **no** attempts bump; a review bounce is
  expected iteration, not a failure. The re-implementer receives the review
  comment verbatim as the fix instruction.

If the reviewer times out, the card returns to `Ready for Review`. If the
reviewer idles without a `VERDICT:` line, nothing is rescued and the normal
timeout applies.

### 4. You: human review and merge

Cards in `Human Review` passed everything. You:

- inspect the diff (branch `ai/<cardId>`),
- merge it into the repo's mainline however you normally do,
- move the card to `Done` — or `Rejected` if you disagree.

G3 **soft** flags are decided here: the dispatcher flagged protected-but-not-
fatal files loudly in the comments; you are the decider.

### 5. Cleanup phase

On every dispatch run, for each `Done` card the dispatcher removes the
worktree and deletes the `ai/<cardId>` branch.

### Reading a card's history

The comment stream is the communication channel and tells the whole story:

```
🚀 Dispatched (...)            ← dispatcher, per attempt
⚠️/⛔ Gate ... comments         ← dispatcher gates
## Report (auto-captured ...)  ← implementer's final transcript output
## AI Review ...               ← reviewer's verdict (auto-captured)
✅ Gates passed / ✅ AI review: APPROVE   ← dispatcher
🔁 bounced / 🛑 rejected       ← dispatcher
```

**When a ticket bounces, read the comments before re-dispatching or editing
it** — the failing gate (G1/G2/G3) or the reviewer's CHANGES REQUESTED text
is named there.

## Operating the pipeline

```bash
SKILL=<path to this skill>

$SKILL/scripts/dispatch.sh status      # board overview
$SKILL/scripts/dispatch.sh run         # full pass: implement + review + cleanup
$SKILL/scripts/dispatch.sh implement   # only the implementation phase
$SKILL/scripts/dispatch.sh review      # only the AI-review phase
$SKILL/scripts/dispatch.sh cleanup     # only worktree/branch cleanup
```

`run` is idempotent and lock-protected (`flock`), so it is safe to overlap.
The intended trigger is cron:

```cron
*/30 * * * * <path to this skill>/scripts/dispatch.sh run >> ~/.config/planka-development-flow/dispatch.log 2>&1
```

Cron runs log to `~/.config/planka-development-flow/dispatch.log`; interactive
runs log to stderr with timestamps.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Card stuck in `Claimed` / `In Progress` | A previous run was killed mid-flight; the next run won't pick it up (not in `Ready`). Inspect `herdr agent list` / `herdr agent read <agent> --source recent --lines 200`, then move the card back to `Ready` manually: `plnk card move <id> --to-list <readyListId>`. |
| `no eligible cards` but cards sit in `Ready` | The `project` field value doesn't match any `PROJ_<name>_repo` key (non-alphanumerics → `_`), or `attempts >= MAX_ATTEMPTS`. |
| Review/implementation keeps bouncing | Read the card comments; the failing gate (`G1`/`G2`/`G3`) or the reviewer's requested changes are named there. |
| `incomplete config` error | `config.env` has empty placeholders — finish the setup steps or re-run `setup-board.sh` (it never overwrites; edit the existing file). |
| Agent seems stuck | `herdr agent read <name> --source recent --lines 200` is the post-mortem tool. Agents are found via `herdr workspace list` (labels `impl-<cardId>` / `review-<cardId>`) + `herdr agent list`. |
| Implausible diff for a small ticket | Worktree branched from a dirty state. Verify `PROJ_<key>_base_ref` points at a clean mainline; worktrees must never branch from HEAD. |

## Extending the system

- **Prompt changes** → `scripts/prompts/{implementer,reviewer}.txt`
  (placeholders are substituted by `dispatch.sh`).
- **New gates / phases** → `scripts/dispatch.sh`, and document them in
  [references/gates.md](references/gates.md).
- **New repo** → add `PROJ_<name>_*` keys to the config; no code changes.
- **Keep the core rule** — deterministic work in the script, fuzzy work in
  agents. Before letting an agent do something new, ask whether the script
  can do it instead (see [references/lessons.md](references/lessons.md)).
