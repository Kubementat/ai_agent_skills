---
description: Run a sequential research → plan → implement → review sub-agent pipeline for a coding task
argument-hint: "<task description>"
---

Task to work on: $1

Orchestrate this task as a strict sequential pipeline of sub-agents. Run exactly one sub-agent at a time (local hardware is limited — no parallelism). Wait patiently for each to fully finish; token speed is slow on this box, so do not interrupt or restart a running agent.

# Pipeline

1. **Research** — sub-agent: research everything needed to accomplish the task well, given this repo's structure. Write findings to `.agent-work/research.md`.
2. **Plan** — sub-agent: load the `karpathy-guidelines` skill first. Read `.agent-work/research.md` and this repo's structure, then write a concrete, well-defined implementation plan to `.agent-work/plan.md`. If something relevant already exists in the repo, decide whether to replace or improve it and say why.
3. **Implement** — sub-agent: load the `karpathy-guidelines` skill first. Execute `.agent-work/plan.md` end to end. Add proper documentation and test the result.
4. **Review & polish** — sub-agent: load the `karpathy-guidelines` skill first. Review all changes from step 3, then improve and simplify the code to make it correct and minimal.

# Rules

- Pass work forward via the files in `.agent-work/` (plus file paths of anything created), not by copying large text between prompts.
- If a step fails or returns something broken, re-run that step once with a note about what went wrong; do not skip it.
- Do no research, planning, or implementation yourself — only orchestrate.

When the pipeline finishes, print a summary for the user: what each stage did, the files created/changed, how it was tested, and any open issues or assumptions.
