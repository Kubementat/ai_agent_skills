# Lessons learned (from the 2026-10-02 test runs)

These findings shaped the architecture. Keep them in mind when extending.

## 1. Agents do not reliably post report comments (4/4 failures)

A 35B local model followed "move the card" but dropped
the "post a comment first" step in **every** run, implementer and reviewer alike.
Fix: the pipeline owns reporting. `dispatch.sh` checks the comment count after
each agent run and auto-captures the agent's final transcript from herdr
(`herdr agent read <agent> --source recent`) if nothing was posted.
**Rule: agents get exactly one plnk mutation — the card move.**

## 2. Never branch worktrees from repo HEAD

The test repo sat on a feature branch well ahead of main. Branching from HEAD
contaminated the ticket branch with unrelated commits; the AI reviewer
correctly flagged an implausibly large diff for a tiny ticket. Fix: per-repo
`base_ref` in config, always.

## 3. The AI review stage earns its keep

The reviewer caught the Dockerfile constraint violation twice (the implementer
kept "helpfully" wiring ldflags into the Dockerfile against an explicit
constraint), forced a clean fix, and approved the corrected 4-file diff. The
bounce loop (review comment → re-implementer reads it → fixes exactly that)
works — the comment is the handoff.

## 4. Constraints need to be absolute in the prompt

"Keep changes minimal" is advice; "the Constraints section is ABSOLUTE, touching
a forbidden file is a failure" is a rule. The hardened prompt stopped most
scope creep, but G3 remains the backstop — prompt discipline is not enforcement.

## 5. Card state is the best progress signal

Polling the card's list via `plnk card get` is more reliable than parsing agent
transcripts or herdr statuses: the agent's contract *is* to move the card, and
the dispatcher only needs "did it leave In Progress / In AI Review".

## 6. herdr specifics that matter

- `run-pi-herdr.sh --no-wait` fires the agent and returns; the dispatcher then
  polls card state (not herdr).
- Agent names are auto-generated (`pi-<model-slug>-<suffix>`); resolve them via
  `herdr workspace list` (label → id) + `herdr agent list` (workspace → agent).
  Workspace labels are `impl-<cardId>` / `review-<cardId>`.
- Workspaces are kept open by default — the dispatcher closes them after each
  run (`herdr workspace close`).
- `herdr agent read <name> --source recent --lines 200` is the post-mortem
  tool for any stuck/failed run.

## 7. Gate independence

Gates run in the dispatcher, not the agent: the dispatcher re-runs the test
command itself (the agent's "all tests pass" claim is input, not evidence),
re-counts commits, and diffs the branch itself. This is what makes the
classical/agentic split safe.

## 8. Agents can drop the card move itself (2026-10-03, reviewer)

Lesson 1 assumed the card move was the one reliable agent action. It is not
always: a reviewer produced a complete, correct APPROVE report and then ended
its turn without running `plnk card move`. Without a rescue the card sat in
`In AI Review` until the full `CARD_TIMEOUT` (1 h) before bouncing back for a
re-review. Fix: the dispatcher polls the herdr agent status alongside the
card; when the agent is idle (turn ended) but the card hasn't moved, it reads
the transcript and completes the move from deterministic evidence (`VERDICT:`
line for reviews, `STATUS:` marker / commit count for implementations). The
gates remain the authority — the rescue only supplies the move.
**Rule: never make the pipeline wait on an agent that has stopped.
