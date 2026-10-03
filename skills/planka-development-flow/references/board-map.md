# Board map — required structure

The dispatcher needs a Planka board with exactly this shape. Nothing else is
custom: any Planka instance works.

- Project (default name: `AI-Orchestration`)
  - Board (default name: `Dispatch Board`)

## Lists (left → right, in this order, with exactly these names)

| # | List | Role in the flow |
|---|---|---|
| 1 | `Inbox` | unworked tickets |
| 2 | `Ready` | eligible for implementation (the dispatch gate) |
| 3 | `Claimed` | claimed by a dispatcher run (transient) |
| 4 | `In Progress` | implementer agent is working |
| 5 | `Ready for Review` | implementation done, gates passed |
| 6 | `In AI Review` | reviewer agent is working (transient) |
| 7 | `Human Review` | APPROVE landed here — you merge & decide |
| 8 | `Done` | merged; dispatcher cleans up worktree/branch |
| 9 | `Rejected` | attempts exhausted |

`dispatch.sh status` and the prompts assume these exact names and order.

Order matters visually; `setup-board.sh` normalizes it — Planka inserts new
lists at the front (smallest position), so boards created without explicit
positions come out reversed. The script sets positions 65536·2ⁿ and is
idempotent; it also repairs reversed boards on re-run.

## Custom fields (project-level base group named `Dispatch`)

| Field | Show on front | Value convention |
|---|---|---|
| `project` | yes | must match a `PROJ_<name>_repo` config key |
| `attempts` | no | integer, incremented on every bounce, reject at `MAX_ATTEMPTS` |

Cards must have the base group adopted
(`plnk field-group create --card <id> --base <baseGroupId>`) before field
values can be set — `new-card.sh` does this automatically.

Planka field model gotcha: adopted card groups have `name: null` and no
fields of their own — the fields live on the base group. Always look up field
IDs via the base group.

## Worktrees and branches

- Worktree: `<WT_ROOT>/<project>/<cardId>` (config `WT_ROOT`)
- Branch: `ai/<cardId>`, always created from the repo's `base_ref` (config), **never** from HEAD

## Creating the board / finding IDs

**Recommended:** `scripts/setup-board.sh` — idempotent, creates whatever is
missing and prints a ready-to-paste config snippet.

By hand (`plnk` must be authenticated):

```bash
plnk project find --name "AI-Orchestration" --output json        # or: plnk project create --name ...
plnk board find --project <projId> --name "Dispatch Board" --output json
plnk list create --board <boardId> --name "Inbox"                # ×9, in order
plnk field-group create --project <projId> --name "Dispatch"
plnk field create --base-group <baseId> --name project --show-on-front
plnk field create --base-group <baseId> --name attempts
```

Then put the IDs into `~/.config/planka-development-flow/config.env`
(template: `config/config.env.example`).
