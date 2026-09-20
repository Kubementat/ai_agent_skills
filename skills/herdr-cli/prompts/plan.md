Load the `karpathy-guidelines` skill first (if available).

Read `.agent-work/task.md` and `.agent-work/research.md`. Explore the repo
further as needed.

Write a concrete, well-defined implementation plan to `.agent-work/plan.md`:

- Ordered steps. Each step states: goal, exact files to touch, the specific
  changes, and a verification command for that step.
- Steps must be small and independently verifiable (roughly 1–3 files each).
  An implementer with limited ability will follow this plan literally — no
  step should require judgment the plan doesn't provide.
- If something relevant already exists in the repo, decide whether to
  replace or improve it and say why.
- End with:
  - `## Acceptance checklist` — checkable items defining "done"
  - `## Test commands` — the exact commands to run at the end to verify the
    whole task

Rules:
- Write ONLY `.agent-work/plan.md`. Do not modify source code.
- Prefer the simplest approach that meets the task; no speculative
  features, no refactoring beyond what the task needs.
