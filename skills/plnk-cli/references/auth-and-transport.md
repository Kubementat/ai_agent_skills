# Auth and Transport Reference

Condensed from upstream `docs/cli/auth.md` and `docs/cli/transport.md`. No network access
needed — this file is the local copy.

## Authentication

`plnk` stores automation/AI-oriented CLI credentials **separately** from `plnk-tui`'s human
login hints. `plnk init` configures the CLI only.

### Credential precedence

First match wins:

| Priority | Method | Server | Token |
|----------|--------|--------|-------|
| 1 | CLI flags | `--server <url>` | `--token <token>` |
| 2 | Environment | `PLANKA_SERVER` | `PLANKA_TOKEN` |
| 3 | Config file | `~/.config/plnk/config.toml` | `~/.config/plnk/config.toml` |

- Config location honors `XDG_CONFIG_HOME`; override with `PLANKA_CONFIG=<path>`.
- On Unix the config file is written `0600`.
- Legacy path `~/.config/planka/config.toml` is still read once and migrated to `plnk/`.
- Token calls use the **`X-API-Key`** header — not `Bearer`, not `Authorization`.

### Setup paths

```bash
plnk init                                        # interactive: server URL + token (masked)
plnk auth login --server https://planka.example  # email + password -> stored token
plnk auth token set <token> --server https://planka.example
export PLANKA_SERVER=https://planka.example      # stateless, good for CI
export PLANKA_TOKEN=your-api-key
```

API tokens are created in the Planka web UI under *Profile → Settings → Tokens*.

### Diagnostic commands

```bash
plnk auth status    # credential source + validity; ALWAYS exits 0 (informational)
plnk auth whoami    # validates token against server; exits 3 on auth failure
plnk auth logout    # delete stored credentials
```

Use `whoami`, not `status`, as a pre-flight gate in scripts — `status` never fails.

### `plnk-tui` is separate

The TUI does not read the CLI config. It prompts for server/username/password on first run and
may save only non-secret server + username to `~/.config/plnk-tui/config.toml` (never the
password). Its env vars are `PLNK_TUI_SERVER`, `PLNK_TUI_USERNAME`, `PLNK_TUI_PASSWORD`,
`PLNK_TUI_BOARD`.

## Transport policy

Defaults are intentionally conservative for self-hosted Planka:

| Setting | Default | Meaning |
|---|---|---|
| `max_in_flight` | `8` | Max concurrent requests per client instance |
| `rate_limit_per_second` | `10` | Sustained request rate |
| `burst_size` | `10` | Short-burst allowance |
| `retry_attempts` | `2` | Retries after the initial request |
| `retry_base_delay_ms` | `250` | Base retry delay |
| `retry_max_delay_ms` | `2000` | Max retry delay |
| `retry_jitter` | `true` | Jittered retry delay |
| `retry_safe_methods_only` | `true` | Retries limited to safe methods |

### Retry behavior

- Retried automatically: `GET`, `HEAD`, `OPTIONS` only (by default).
- Retryable statuses: `429`, `502`, `503`, `504`, plus `reqwest` timeout/connect failures.
- **Writes are not retried**: `POST`, `PATCH`, `DELETE`.
- Never retried: `404`, `401`, malformed requests, other non-transient failures.
- `Retry-After` is honored when parseable (clamped to a sane upper bound).

Practical consequence: a failed write is failed for real — re-check state before retrying a
create/update by hand.

### Tuning knobs

Resolution order: CLI flags → env vars → config file → built-in defaults.

```bash
--http-max-in-flight <n>   --http-rate-limit <rps>   --http-burst <n>
--retry-attempts <n>       --retry-base-delay-ms <ms> --retry-max-delay-ms <ms>
--no-retry                 # forces retry_attempts = 0
```

```text
PLNK_HTTP_MAX_IN_FLIGHT  PLNK_HTTP_RATE_LIMIT  PLNK_HTTP_BURST
PLNK_RETRY_ATTEMPTS      PLNK_RETRY_BASE_DELAY_MS  PLNK_RETRY_MAX_DELAY_MS
```

```toml
# ~/.config/plnk/config.toml
server = "https://planka.example.com"
token  = "your-api-token"

[http]
max_in_flight = 8
rate_limit = 10
burst = 10
retry_attempts = 2
retry_base_delay_ms = 250
retry_max_delay_ms = 2000
```

Valid ranges: `max_in_flight 1..=64` · `rate_limit 1..=1000` · `burst 1..=1000` (requires
`rate_limit`) · `retry_attempts 0..=10` · `retry_base_delay_ms 1..=60000` ·
`retry_max_delay_ms 1..=60000`. Invalid values fail fast.
