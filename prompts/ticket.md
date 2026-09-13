---
description: Generate implementation tickets from spec or chat context
argument-hint: "[<file-path> | --from-chat]"
---
Generate implementation tickets compatible with the `ticket-implement` chain.

## Input Source

Choose one:
1. **File**: If a path is provided (e.g., `/ticket path/to/spec.md`), read it as the source.
2. **Chat history**: If no path or `--from-chat` is given, analyze the current conversation for requirements discussed.

## First Step

${1:+
**🔴 CRITICAL — READ THIS FILE FIRST:**

Use the `read` tool to read the file at: **`$1`**

Do NOT generate tickets until you have read the file. The file contains the spec you need to generate tickets from.

After reading the file, proceed with generating tickets based on its contents.
}

${1:-
**No file path provided.** Analyze the current conversation for requirements and generate tickets from chat context.
}

## Ticket Format

For each distinct requirement found, create a ticket file at `.tickets/<order-number><feature-name>/<ticket-id>.md` with this structure:

```markdown
---
ticket: <ticket-id>
feature: <feature-name>
status: pending
---

# <Title>

## Requirements

- [ ] <requirement 1>
- [ ] <requirement 2>

## Acceptance Criteria

- [ ] <criterion 1>
- [ ] <criterion 2>

## Notes

<any additional context, constraints, or implementation hints>
```

## Ticket ID Convention

Use format: `<order-number>-<module>-<sequence>` (e.g., `vm-01`, `config-02`, `auth-03`)

## Rules

1. Each ticket must be **atomic** — one logical unit of work.
2. Tickets should describe a Test Driven approach (TDD). If applicable tests should be implemented first
3. Split complex requirements into sub-tickets if needed.
4. Include dependencies between tickets as notes.
5. Set `status: pending` for all generated tickets.
6. Do not modify `status`, `started`, or `completed` fields — the chain handles that.
7. If multiple tickets are generated, list them at the end with their IDs.
8. Tickets MUST BE numbered sequentially using an `order-number` prefix starting with `01` onwards

## Output

1. Create all ticket files in `.tickets/<feature-name>/`.
2. Print a summary of generated tickets.
3. Offer to run `ticket-implement` chain on them.
