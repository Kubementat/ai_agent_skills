# Card format contract

The description of a ticket in `Ready` is the machine-readable input.
The implementer agent works from it; the reviewer checks it against.

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
- Do not touch X / Y (these should mirror the config's protected patterns)
- Do not bump dependencies
- Keep the change minimal
```

Rules:

- **Acceptance criteria must be verifiable** — the reviewer checks each one
  individually and reports met/not met. "Works correctly" is not a criterion;
  "`GET /version` returns JSON with a `version` field" is.
- **Constraints are absolute** for the implementer and enforced by the reviewer.
  If a constraint would make the ticket impossible, fix the ticket, not the agent.
- The `project` custom field (set by `new-card.sh`) is the machine link between
  the card and the repo config — it takes precedence over the `## Repo` line.
- The reviewer's CHANGES REQUESTED comment is fed back to the re-implementer
  verbatim — write issues you would want to be acted on precisely.

## Comments are the communication channel

The full history on a card tells the story:

```
🚀 Dispatched (...)            ← dispatcher, per attempt
⚠️/⛔ Gate ... comments         ← dispatcher gates
## Report (auto-captured ...)  ← implementer's final transcript output
## AI Review ...               ← reviewer's verdict (auto-captured)
✅ Gates passed / ✅ AI review: APPROVE   ← dispatcher
🔁 bounced / 🛑 rejected       ← dispatcher
```

When a ticket bounces, read the comments before re-dispatching or editing it.
