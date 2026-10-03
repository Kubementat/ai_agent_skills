# Board map — live IDs

Server: `https://planka.denkfabrik.space/`
Project: `AI-Orchestration` — `1877211143563379717`
Board: `Dispatch Board` — `1877212014779040775`

## Lists (left → right)

| List | ID | Position |
|---|---|---|
| Inbox | `1877212080554116107` | 1000 |
| Ready | `1877212081032266764` | 2000 |
| Claimed | `1877212081476862989` | 3000 |
| In Progress | `1877212081896293390` | 4000 |
| Ready for Review | `1877212082332501007` | 5000 |
| In AI Review | `1877225921337885729` | 5500 |
| Human Review | `1877225921774093346` | 7000 |
| Done | `1877225922260632611` | 8000 |
| Rejected | `1877212082768708624` | 9000 |

## Custom fields (base group `Dispatch`)

Base group: `1877213044086408210` (project-level template; cards adopt it)

| Field | ID | Show on front | Value convention |
|---|---|---|---|
| `project` | `1877213106237604883` | yes | must match a `PROJ_<name>_repo` config key |
| `attempts` | `1877213106724144148` | no | integer, incremented on every bounce, reject at `MAX_ATTEMPTS` |

Cards must have the base group adopted (`plnk field-group create --card <id> --base 1877213044086408210`)
before field values can be set — `new-card.sh` does this automatically.

## Worktrees and branches

- Worktree: `/home/verfeinerer/dev/worktrees/<project>/<cardId>`
- Branch: `ai/<cardId>`, always created from the repo's `base_ref` (config), **never** from HEAD
