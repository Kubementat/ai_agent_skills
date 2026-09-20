Load the `karpathy-guidelines` skill first (if available).

You are reviewing and finishing work done by another agent. Read
`.agent-work/task.md`, `plan.md`, and `results.md` in `.agent-work/`.
Do not trust anything the previous agent claimed — verify it.

Steps (in this order):
1. Re-run every verification/test command from `results.md` and from the
   `## Test commands` section of `plan.md` yourself. Compare against the
   recorded output.
2. Review the full set of changes (`git status` and `git diff`, plus any
   untracked files) for correctness, minimalism, and leftover junk
   (debug prints, dead code, stray files).
3. Fix everything that is broken, failing, or incomplete. You have full
   write access. Re-run the tests until they pass.
4. Simplify where you can without changing behavior.

Write `.agent-work/review.md`:

## Verification
Commands re-run, with actual output.

## Fixes applied
## Simplifications
## Open issues
Anything you could not fix, with the reason. Write "none" if there are
none.

Final line — exactly one of:
STATUS: clean
STATUS: open:<n>

`STATUS: clean` only if all tests pass and there are no open issues.
