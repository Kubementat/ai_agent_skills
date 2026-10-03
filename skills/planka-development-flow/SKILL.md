---
name: planka-development-flow
description: Orchestrate the Planka-based AI development workflow — create tickets, dispatch them to agentic implementer/reviewer sessions, and track them through the board (Inbox → Ready → Claimed → In Progress → Ready for Review → In AI Review → Human Review → Done/Rejected). Use when the user says "dispatch the board", "run the planka flow", "create a ticket", "planka status", works on Planka tickets, or asks about the AI ticket pipeline. The classical dispatcher script does all deterministic work; agents only implement and review.
---

# planka-development-flow

A ticket pipeline where **Planka is the system of record** and **agents are workers**.
A classical bash script (`dispatch.sh`) does everything deterministic — polling,
claiming, worktrees, gates, reporting, cleanup. The only agentic parts are the
implementation session and the AI-review session, launched via herdr.

```
You:       Inbox ──► Ready           (write ticket, you decide what gets worked)
dispatch:  Ready ──► Claimed ──► In Progress ──► (agent implements)
gates:     G1 commits · G2 tests · G3 protected files · G4 state + report
dispatch:  ──► Ready for Review ──► In AI Review ──► (agent reviews)
AI review: APPROVE ──► Human Review      CHANGES ──► Ready (bounce, attempts++)
You:       Human Review ──► Done (merge branch)  |  Rejected
dispatch:  (next run) cleans worktrees + branches of Done cards
```

Board: `Dispatch Board` in the `AI-Orchestration` project on
`https://planka.denkfabrik.space/`. All IDs in [references/board-map.md](references/board-map.md).

## Quick start

```bash
SKILL=/home/verfeinerer/skills/ai_agent_skills/skills/planka-development-flow

$SKILL/scripts/dispatch.sh status      # board overview
$SKILL/scripts/dispatch.sh run         # full pass: implement + review + cleanup
$SKILL/scripts/new-card.sh --title "Add /foo" --project ai-proxy-king --desc /tmp/ticket.md
```

**Cron** (the intended periodic trigger — idempotent, lock-protected, safe to overlap):

```cron
*/30 * * * * /home/verfeinerer/skills/ai_agent_skills/skills/planka-development-flow/scripts/dispatch.sh run >> ~/.config/planka-dispatch/dispatch.log 2>&1
```

## Creating tickets

1. Write the ticket as markdown following the format contract:
   [references/card-format.md](references/card-format.md)
2. `new-card.sh --title "..." --project <name> --desc file.md [--list inbox|ready]`
   — creates the card, adopts the `Dispatch` field group, sets the `project` field.
3. Tickets in **Ready** are the gate: only cards you put there get worked.

`project` field values must match a `PROJ_<name>_repo` key in the config
(see below). Cards with unknown projects are skipped (not bounced).

## Config

`~/.config/planka-dispatch/config.env` (bash-sourced, no parser).
Example: `config/config.env.example`. Per-project settings:

```bash
# key = project field value with non-alphanumerics -> _  (ai-proxy-king -> ai_proxy_king)
PROJ_ai_proxy_king_repo=/home/verfeinerer/dev/os_projects/ai-proxy-king
PROJ_ai_proxy_king_base_ref=main
PROJ_ai_proxy_king_test=go test ./...
PROJ_ai_proxy_king_hard=.env* *.pem keys/* secrets/*
PROJ_ai_proxy_king_soft=Dockerfile docker-compose.yml .gitlab/* .gitlab-ci.yml go.mod go.sum
```

| Key | Meaning |
|---|---|
| `MAX_PARALLEL` | tickets in flight per dispatch run (default 2) |
| `MAX_ATTEMPTS` | bounces allowed before Rejected (default 3) |
| `CARD_TIMEOUT` | seconds to wait for one agent (default 3600) |
| `MODEL` | herdr/pi model for implementer + reviewer |
| `HERDR_RUN` | path to `run-pi-herdr.sh` |
| `WT_ROOT` | worktree root (`<root>/<project>/<cardId>`) |
| `*_hard` | file globs — touching any → bounce (gate G3 hard) |
| `*_soft` | file globs — touching any → flag comment, continues (gate G3 soft) |

## How dispatch works

Phases (details in [references/gates.md](references/gates.md)):

- **implement** — pick up to `MAX_PARALLEL` eligible Ready cards (project known,
  attempts < max), claim each (`Ready → Claimed → In Progress`), create the git
  worktree from `base_ref` (never HEAD), launch implementer agents in parallel
  via herdr, poll card state, then run gates G1–G4 and the report check.
- **review** — same pattern for `Ready for Review` cards, with the reviewer agent.
  APPROVE → `Human Review`; CHANGES REQUESTED → `Ready` (re-implementation reads
  the review comment).
- **cleanup** — remove worktrees + `ai/<cardId>` branches of `Done` cards.

Key design rule (learned the hard way — see [references/lessons.md](references/lessons.md)):
**agents never post their own report comments.** The script checks after each
run and auto-captures the agent's final transcript output from herdr if the
comment is missing. The card move is the agent's only `plnk` mutation.

## Prerequisites

- `plnk` CLI on PATH with valid token (`plnk auth whoami`)
- `herdr` server running (`herdr status`; start: `nohup herdr server > /tmp/herdr-server.log 2>&1 &`)
- `run-pi-herdr.sh` (herdr-cli skill) at `$HERDR_RUN`
- git, jq, flock

## Troubleshooting

- `dispatch.sh status` shows cards stuck in `Claimed`/`In Progress` → a previous
  run was killed mid-flight; the next `run` will not pick them up (they are not
  in Ready). Inspect with `herdr agent list`, then move the card back to Ready
  manually (`plnk card move <id> --to-list <readyListId>`).
- Review/implementation keeps bouncing → read the card comments; the gate that
  failed is named in the bounce comment (`G1`/`G2`/`G3`).
- `no eligible cards` but there are cards in Ready → check the `project` field
  value matches a config key, and `attempts` < `MAX_ATTEMPTS`.
- Log file for cron runs: `~/.config/planka-dispatch/dispatch.log`

## Extending

This skill is the home of the system. When improving it:

- prompt changes → `scripts/prompts/{implementer,reviewer}.txt`
- new gates/phases → `scripts/dispatch.sh` (document in references/gates.md)
- new repo → add `PROJ_<name>_*` keys to the config
- keep the core rule: **deterministic work in the script, fuzzy work in agents**
