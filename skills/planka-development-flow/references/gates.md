# Gates and phases

Everything deterministic happens in `dispatch.sh`. The agent's self-report is
never trusted; the card state plus independent checks are.

## Phase: implement

1. **Eligibility** — card in `Ready`, `project` field set and known in config,
   `attempts < MAX_ATTEMPTS`. Ineligible cards are skipped (with a log line),
   never bounced.
2. **Claim** — `Ready → Claimed → In Progress`. The move is the lock: a card
   leaves Ready before the agent starts, so a second dispatch run (or cron
   overlap) cannot claim it. `flock` on the lockfile makes overlapping runs
   no-ops anyway.
3. **Worktree** — `<WT_ROOT>/<project>/<cardId>` on branch `ai/<cardId>`,
   created from the config `base_ref` (existing worktrees/branches are reused
   on re-dispatch after a bounce).
4. **Launch** — `run-pi-herdr.sh --no-wait` (or `runagent` with sandbox) with
   the implementer prompt (`scripts/prompts/implementer.txt`, placeholders
   substituted). Up to `MAX_PARALLEL` agents run concurrently.
5. **Wait** — poll `plnk card get` every `POLL_INTERVAL` seconds until the card
   leaves `In Progress` (or `CARD_TIMEOUT`). If the agent **ends its turn
   without moving the card** (agent idle, see lesson 8), the dispatcher
   *rescues*: after a 120s grace period it reads the transcript and completes
   the move from deterministic evidence — `STATUS: FAILED` marker → Ready;
   ≥1 commit on the branch → Ready for Review (gates still apply); otherwise →
   Ready (failure).
6. **Gates** (see below).
7. **Report check** — if no new comment appeared, auto-capture the agent's
   final transcript (`herdr agent read <agent> --source recent`) and post it
   as `## Report (auto-captured by dispatcher ...)`.
8. **Workspace close** — `herdr workspace close` the agent's workspace.

## Gate chain (implementation)

| Gate | Check | Failure action |
|---|---|---|
| G1 | `git rev-list --count <base_ref>..HEAD` ≥ 1 | bounce |
| G2 | config `test_command` passes in the worktree (dispatcher runs it, tail of output in comment) | bounce |
| G3 hard | no diff file matches `*_hard` globs | bounce |
| G3 soft | diff files matching `*_soft` globs | **flag comment only, continues** (human decides at Human Review) |
| G4 | card is in `Ready for Review` (agent moved it) | bounce |

Card ended in `Ready` (agent self-reported failure) → bounce without gates.

## Bounce / reject

```
attempts++ (custom field)
attempts < MAX_ATTEMPTS → back to Ready   (re-dispatch reuses worktree/branch;
                                          re-implementer reads the review/gate
                                          comments and fixes)
attempts >= MAX_ATTEMPTS → Rejected
```

## Phase: review

Same claim/launch/wait machinery on `Ready for Review` cards:

1. `Ready for Review → In AI Review`
2. reviewer agent (read-only for code; in runagent mode the worktree is
   OS-enforced read-only via asb `--ro-bind`). Its only mutation is the card move.
3. report check (auto-capture the verdict if the comment is missing)
4. `Human Review` (APPROVE) or `Ready` (CHANGES REQUESTED — no attempts bump;
   the review bounce is expected iteration, distinct from gate bounces)
5. idle rescue as in implementation, using the `VERDICT:` line of the
   reviewer's final message; if the agent is idle but no verdict line is
   found, no move is made and the normal timeout applies
6. review timeout → card returns to `Ready for Review` (not a failure)

## Phase: cleanup

For every card in `Done`: remove the worktree, delete the `ai/<cardId>` branch.
(You merge the branch into the repo's mainline yourself before moving to Done.)

## Why the two-tier G3

Hard globs protect things that must never change (secrets, keys). Soft globs
mark files that *default* to do-not-touch but where the agent's change might
legitimately be wanted (Dockerfile for a feature that needs build metadata).
The test runs showed a hard gate on soft files destroys good work; a human at
Human Review is the right decider for judgment calls. The dispatcher flags them
loudly either way.
