Load the `karpathy-guidelines` skill first (if available).

Read `.agent-work/task.md` and `.agent-work/plan.md`. Execute the plan end
to end.

Rules:
- Follow the plan step by step. After each step, run its verification
  command before moving on.
- If a step is not workable as written, make the smallest sensible
  adjustment and note the deviation in `results.md`. Do not redesign the
  approach.
- Add or update documentation and tests where the plan calls for them.
- Do not touch files the plan does not mention unless a step requires it.

When finished (or if you are stuck and cannot proceed), write
`.agent-work/results.md`:

## Steps completed
One line per plan step: done / adjusted / skipped, with a short note.

## Test output
Paste the ACTUAL output of every verification and test command you ran.
Do not paraphrase or summarize — raw output, including failures.

Final line — exactly one of:
RESULTS: all-pass
RESULTS: <n>-failed

Rules for the final line:
- `RESULTS: all-pass` only if every verification command exited 0 and the
  acceptance checklist in `plan.md` is satisfied.
- Never write `all-pass` to make the pipeline continue. A truthful
  `RESULTS: N-failed` with real output is always better.
