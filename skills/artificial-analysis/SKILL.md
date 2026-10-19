---
name: artificial-analysis
description: Query the Artificial Analysis Data API (artificialanalysis.ai) to compare LLMs side by side, rank models by intelligence / coding / agentic index / speed / price, search the model catalog, and find the best open-weights models that fit a local hardware budget (e.g. 128 GB unified-memory AMD Strix Halo). Use when the user asks about model benchmarks, the Artificial Analysis Intelligence Index, model pricing or tokens-per-second, "which model is best for X", "which open-weight model fits my hardware", or mentions artificialanalysis.ai.
---

# artificial-analysis

Stdlib-only client (`scripts/aa.py`) for the Artificial Analysis Data API. It answers three
kinds of question:

1. **Compare** — head-to-head benchmark, capability, speed and price table for named models.
2. **Rank / search** — sort the catalog by intelligence, coding, agentic index, speed or price.
3. **Local fit** — which *open-weights* models actually fit a given RAM budget at a given
   quantisation, so the user knows what to download for a llama.cpp / vLLM box.

## Prerequisites

```bash
python3 --version                                    # 3.8+, standard library only
echo "$AA_API_KEY" | head -c 4                       # key present? (never print the whole key)
```

An API key is needed for live calls only — get a free one at
<https://artificialanalysis.ai/data-api>. `--help` and `--fixture-dir` work with no key and
no network.

## Key resolution

Checked in this order, first match wins. The key is never printed or logged.

1. Environment variable `AA_API_KEY`
2. `~/.config/artificialanalysis/config.env`, any line of the form `AA_API_KEY="..."`
   (also accepts `ARTIFICIAL_ANALYSIS_API_KEY`, `api_key`, `API_KEY`, and a leading `export`)

If neither exists the command exits 1 and names both locations.

## Tier and rate-limit situation (important)

- Base URL `https://artificialanalysis.ai/api/v2`, auth header `x-api-key`.
- **Free tier: 100 requests per fixed 24-hour window**, shared across the whole org scope.
  Responses carry `X-RateLimit-Limit/Remaining/Reset` and `X-AA-Tier`; `aa.py` prints
  `AA rate limit remaining: N` to stderr after every live call.
- A `429` response includes `Retry-After`; `aa.py` prints it and exits non-zero. Back off —
  do not retry in a loop, the window is fixed and cannot be reset.
- Pro endpoints (e.g. `/api/v2/language/models`) return **403** on a free key. Only use the
  `.../free` endpoints and `/data/llms/models`.
- The free tier has **no** `open_weights` flag, no context window, no parameter counts and no
  `huggingface_url` (Pro-only). Open-weights status and parameter counts are therefore
  *heuristics* in this skill — see [Open-weights heuristic](#open-weights-heuristic).

**Budget discipline:** develop and test offline with `--fixture-dir`. One `models` query costs
1 request plus one per page of the paginated free endpoint (4 pages at page_size 200). The
cache (below) makes repeats free.

## Caching

Every live response is cached as JSON under the cache directory with a timestamp.

- Default cache dir: `~/.cache/artificial-analysis` (override with `--cache-dir DIR`)
- TTL: 21600 s (6 h), override with env `AA_CACHE_TTL_SECS`
- `--refresh` ignores the cache and re-fetches (still writes it back)
- `--fixture-dir` makes **zero** HTTP requests and reads nothing from the cache

## Global flags

```text
aa.py [--cache-dir DIR] [--refresh] [--fixture-dir DIR] [--json] <subcommand> ...
```

The four global flags are accepted before *or* after the subcommand. `--json` emits machine
readable output instead of a table (except `raw`, which is always JSON).

Every human-readable output ends with the attribution line required by Artificial Analysis:

```text
Data: artificialanalysis.ai (Intelligence Index v4.3)
```

**Keep that line** whenever you paste results into a report, README, ticket or chat message.

## Subcommands

### 1. `models` — browse and rank the catalog

```bash
aa.py models --limit 15                              # top 15 by intelligence index
aa.py models --min-intel 20 --sort speed
aa.py models --creator deepseek --since 2026-01-01
aa.py models --sort price --json
```

- Filters: `--creator SUBSTR` (matches creator *or* model name), `--min-intel N`,
  `--since YYYY-MM-DD`
- `--sort intel|coding|agentic|speed|price|release` (default `intel`; `price` is cheapest
  first, everything else descending), `--limit N` (default 25)
- Columns: `MODEL CREATOR INTEL CODING AGENTIC TOK/S $/1M OUT RELEASED`
- Data comes from **both** endpoints joined on the stable model `id`

### 2. `compare SLUG [SLUG...]` — side-by-side table

```bash
aa.py compare claude-opus-5-5 gpt-6-astra-xhigh
aa.py compare qwen3-5-27b deepseek-v3-1-terminus-reasoning --json
```

Rows: creator, release date, Intelligence/Coding/Agentic indices, the six Capability Indexes
(finance, strategy/ops, legal, healthcare, engineering, economics), per-benchmark scores
(MMLU-Pro, GPQA, HLE, LiveCodeBench, SciCode, MATH-500, AIME as 0-1 fractions),
input/output/blended price per 1M tokens, median tokens/s, median TTFT, open-weights flag.

Unknown slug → exit non-zero with `difflib` suggestions; slugs may change over time, prefer
model `id`s in scripts (`--json` includes `id`).

### 3. `search TEXT` — substring search

```bash
aa.py search qwen
aa.py search "deepseek" --json
```

Case-insensitive match on model name and creator, prints `MODEL CREATOR INTEL RELEASED`
sorted by intelligence index.

### 4. `open-weights` — what fits on my machine

```bash
# 128 GB unified-memory AMD Strix Halo box ("evobox"), ~120 GB usable for weights
aa.py open-weights --ram 120 --quant q4_k_m
aa.py open-weights --ram 120 --quant q8_0 --limit 10
aa.py open-weights --ram 24 --quant q4_k_m --all
```

- `--ram GB` usable memory for weights (128 GB Strix Halo ⇒ use `--ram 120`)
- `--quant q4_k_m|q5_k_m|q6_k|q8_0|fp16` (default `q4_k_m`)
- `--limit N` (default 25), `--all` also lists models with an unknown parameter count
- Columns: `MODEL CREATOR TOTAL B ACTIVE B INTEL EST WEIGHT GB FITS`, sorted by intelligence

**The `fits` column is an estimate.** Weight memory = total params × bytes/param
(q4_k_m 0.57, q5_k_m 0.63, q6_k 0.77, q8_0 1.00, fp16 2.00) **+ 10 % overhead**. KV cache,
activation memory, context length, multimodal encoders and the ROCm/CUDA runtime are **not**
modelled — on a real Strix Halo run budget 10-30 % headroom, and a long-context Qwen3.5 122B
A10B can fail to load even when `fits=yes`. Command output repeats this disclaimer; keep it in
any answer you give the user.

#### Open-weights heuristic

Because the free tier exposes no open-weights flag, a model is treated as open-weights when:

1. its name matches an `exclude` substring in `assets/open_weights_overrides.json` → **closed**
2. otherwise an `include` substring → **open**
3. otherwise a curated family list (Qwen, DeepSeek, GLM, Llama, Mistral/Mixtral, Gemma,
   Granite, Nemotron, Kimi/Moonshot, MiniMax, Hermes, Phi-4, ERNIE, Aya, Command R, Yi,
   InternLM/InternVL, GPT-OSS, Apertus, OLMo, Magistral, LongCat, Nanbeige, DeepCoder, Arcee,
   Tulu, Sarvam)
4. parameter counts come from `params` in the override file when present, otherwise are parsed
   from the name (`32B` → 32/32, `235B-A22B` and `235B A22B` → 235 total / 22 active)

When you learn a parameter count or an open/closed status that the heuristic gets wrong, add
it to `skills/artificial-analysis/assets/open_weights_overrides.json` (`{"include": [...],
"exclude": [...], "params": {"<slug>": {"total_b": N, "active_b": N}}}`). Overrides always win
over the family heuristic. Say out loud that open-weights status here is a heuristic, not API
data.

### 5. `raw PATH` — any other endpoint

```bash
aa.py raw media/text-to-image/models/free
aa.py raw media/speech-to-text/models/free
aa.py raw media/text-to-video/models/free
aa.py raw language/models/free --param page=2
```

Authenticated **GET** only, under `/api/v2`; accepts a leading `https://artificialanalysis.ai`
or `/api/v2` prefix, refuses path traversal, and refuses anything that is not a 200 JSON body.
Use it for endpoints `aa.py` does not model (image editing, video, music, speech-to-speech).

## Offline mode and tests

`--fixture-dir` replays recorded responses (zero HTTP, no key required):

```bash
FX=skills/artificial-analysis/tests/fixtures
aa.py --fixture-dir "$FX" models --limit 10
aa.py --fixture-dir "$FX" compare gpt-6-astra-xhigh qwen3-5-9b
aa.py --fixture-dir "$FX" open-weights --ram 120 --quant q4_k_m
bash tests/test_artificial_analysis.sh          # offline suite
```

See `skills/artificial-analysis/tests/fixtures/README.md` for what the fixtures contain and
their attribution.

## Operating rules

- Never hit the live API when a cached response will do; never loop on `429`.
- Never echo, log or commit an API key; do not paste `AA_API_KEY` values into tickets.
- Quote numbers with their unit and endpoint family (indices are 0-100, benchmark scores 0-1).
- Always reproduce the attribution line when relaying data from this skill.
- State that open-weights status, parameter counts and `fits` are estimates/heuristics.
