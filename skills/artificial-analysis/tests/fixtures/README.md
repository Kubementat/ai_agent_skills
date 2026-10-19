# Offline fixtures — Artificial Analysis Data API

Recorded responses from the live Artificial Analysis Data API (`https://artificialanalysis.ai/api/v2`)
on **2026-10-19**, trimmed to the models the offline test suite needs. JSON has no comment
syntax, so attribution lives here:

> **Data: artificialanalysis.ai** (Intelligence Index v4.3). These fixtures are recorded API
> output; keep the attribution line when relaying any numbers derived from them.

No API key, request header, or other secret appears in these files — only public model
metadata (names, slugs, indices, prices, throughput).

## Files

| File | Endpoint | Records | Notes |
| --- | --- | --- | --- |
| `legacy_models.json` | `GET /api/v2/data/llms/models` | 30 | Trimmed from 705; keeps the `{status, prompt_options, data}` envelope. |
| `v2_free_page1.json` | `GET /api/v2/language/models/free?page=1` | 23 | Trimmed from 200; `pagination.has_more = true` preserved. |
| `v2_free_page4.json` | `GET /api/v2/language/models/free?page=4` | 4 | Real last page (`page 4/4`, `has_more = false`) so pagination merging is exercised. |
| `media_text_to_image_free.json` | `GET /api/v2/media/text-to-image/models/free` | 6 | Trimmed from 102; used by `raw`. |

The v2 free files add the Agentic Index and the six Capability Indexes; the legacy file adds
per-benchmark scores (MMLU-Pro, GPQA, HLE, LiveCodeBench, SciCode, MATH-500, AIME), blended
price and median TTFT/tokens-per-second. `aa.py` joins the two on the stable model `id`.

## Why these models

- `GLM-4.5 (Reasoning)`, `GLM-4.5-Air` — open-weights GLM family (parameter counts come from
  `assets/open_weights_overrides.json`, since the name carries none).
- `Qwen3 235B A22B 2507 Instruct`, `Qwen3.5 397B A17B (Reasoning)`, `Qwen3.8 2.4T A95B`,
  `Llama 3.1 Tulu3 405B`, `DeepSeek R1 (Jan '25)` — open models far above a 120 GB budget
  (`fits=no`).
- `Qwen3.5 122B A10B (Reasoning)`, `gpt-oss-120b (High)`, `GLM-4.5-Air`, `Qwen3.5 9B (Reasoning)`,
  `gpt-oss-20b (High)`, `Gemma 4 12B (Reasoning)`, `Nemotron 3.5 Bolt 74B-A9B` — open models
  that do fit a 128 GB unified memory box at `q4_k_m` (`fits=yes`).
- `Qwen3.8 2.4T A95B` and `Nemotron 3.5 Bolt 74B-A9B` — real names that broke the parameter
  parser once: `T` means trillion (2.4T = 2400B, not the 95B `A95B` tail) and `3.5` is a version,
  not 3.5B (the size is the `74B` next to `-A9B`). Keep them: `tests/test_artificial_analysis.sh`
  asserts `2400.0`/`no` and `46.4 GB`/`yes` from these rows.
- `Claude Opus 5.5`, `Claude Fable 5.1`, `GPT-6 Astra (Xhigh)`,
  `Gemini 2.5 Pro`, `Grok 4.6 (Medium)` — closed-weight models that `open-weights` must exclude.
- `gpt-6-astra-xhigh` + `qwen3-5-9b` — used by `compare` to prove the id join: both the v2
  Agentic/Capability indexes **and** the legacy GPQA/SciCode scores appear in one table.

## Re-recording

```bash
KEY=$(sed -n 's/^AA_API_KEY="\(.*\)"$/\1/p' ~/.config/artificialanalysis/config.env)
curl -s -H "x-api-key: $KEY" https://artificialanalysis.ai/api/v2/data/llms/models > legacy_models.json
curl -s -H "x-api-key: $KEY" 'https://artificialanalysis.ai/api/v2/language/models/free?page=1' > v2_free_page1.json
```

Free tier: 100 requests per fixed 24 h window — re-record rarely and trim before committing.
