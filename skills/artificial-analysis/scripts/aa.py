#!/usr/bin/env python3
"""aa.py — Artificial Analysis Data API client (Python 3 standard library only).

Compare LLMs side by side, rank models by intelligence / speed / price, and find
open-weights models that fit a local hardware budget.

Data: artificialanalysis.ai — attribution is required on any published result.
Docs: https://artificialanalysis.ai/data-api/docs
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# ─── constants ────────────────────────────────────────────────────────────────

API_BASE = "https://artificialanalysis.ai/api/v2"
LEGACY_MODELS_PATH = "/data/llms/models"
V2_FREE_MODELS_PATH = "/language/models/free"

DEFAULT_CACHE_DIR = os.path.expanduser("~/.cache/artificial-analysis")
CONFIG_ENV_PATH = os.path.expanduser("~/.config/artificialanalysis/config.env")
DEFAULT_TTL_SECS = 21600  # 6 h — the free tier is 100 requests / 24 h
HTTP_TIMEOUT = 30
ATTRIBUTION_BASE = "Data: artificialanalysis.ai"

QUANT_BYTES_PER_PARAM = {
    "q4_k_m": 0.57,
    "q5_k_m": 0.63,
    "q6_k": 0.77,
    "q8_0": 1.00,
    "fp16": 2.00,
}
WEIGHT_MEMORY_OVERHEAD = 1.10  # +10 % for non-weight tensors / alignment

# Families that publish open-weights checkpoints (heuristic: the free API tier
# has no open_weights flag). Name matching is case-insensitive substring.
OPEN_WEIGHT_FAMILIES = [
    "qwen", "deepseek", "glm", "llama", "mistral", "mixtral", "gemma",
    "granite", "nemotron", "kimi", "moonshot", "minimax", "hermes", "phi-4",
    "ernie", "aya", "command r", "yi ", "internlm", "internvl", "gpt-oss",
    "apertus", "olmo", "magistral", "longcat", "nanbeige", "deepcoder",
    "arcee", "tulu", "sarvam",
]

BENCHMARK_LABELS = [
    ("mmlu_pro", "MMLU-Pro"),
    ("gpqa", "GPQA"),
    ("hle", "HLE"),
    ("livecodebench", "LiveCodeBench"),
    ("scicode", "SciCode"),
    ("math_500", "MATH-500"),
    ("aime", "AIME"),
]

CAPABILITY_LABELS = [
    ("finance_and_accounting", "Capability: Finance"),
    ("strategy_and_ops", "Capability: Strategy/Ops"),
    ("legal", "Capability: Legal"),
    ("healthcare_and_medical", "Capability: Healthcare"),
    ("engineering", "Capability: Engineering"),
    ("economics", "Capability: Economics"),
]

ASSETS_DIR = Path(__file__).resolve().parent.parent / "assets"
OVERRIDES_PATH = ASSETS_DIR / "open_weights_overrides.json"


# ─── errors ───────────────────────────────────────────────────────────────────


class AAError(Exception):
    """User-facing failure. Message must never contain the API key."""


class ConfigError(AAError):
    """Missing/invalid local configuration — the request was never attempted."""


class RateLimited(AAError):
    def __init__(self, retry_after):
        super().__init__("Rate limited (HTTP 429). Retry-After: %s seconds." % (retry_after or "unknown"))
        self.retry_after = retry_after


# ─── configuration ────────────────────────────────────────────────────────────


def parse_env_file(path):
    """Parse simple `KEY="value"` / `KEY=value` lines; ignore comments."""
    values = {}
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError:
        return values
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, raw = line.partition("=")
        key = key.strip()
        if key.startswith("export "):
            key = key[len("export "):].strip()
        raw = raw.strip()
        if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
            raw = raw[1:-1]
        if key:
            values[key] = raw
    return values


def resolve_api_key():
    """Env AA_API_KEY first, then ~/.config/artificialanalysis/config.env."""
    key = os.environ.get("AA_API_KEY")
    if key:
        return key.strip()
    cfg = parse_env_file(CONFIG_ENV_PATH)
    for name in ("AA_API_KEY", "ARTIFICIAL_ANALYSIS_API_KEY", "api_key", "API_KEY"):
        value = cfg.get(name)
        if value:
            return value.strip()
    raise ConfigError(
        "No Artificial Analysis API key found.\n"
        "  Set the environment variable AA_API_KEY, or add an AA_API_KEY=\"...\" line to\n"
        "  %s\n"
        "  Get a free key at https://artificialanalysis.ai/data-api" % CONFIG_ENV_PATH
    )


def resolve_ttl():
    raw = os.environ.get("AA_CACHE_TTL_SECS")
    if raw:
        try:
            return max(0, int(float(raw)))
        except ValueError:
            sys.stderr.write("Ignoring invalid AA_CACHE_TTL_SECS=%r, using %d s\n" % (raw, DEFAULT_TTL_SECS))
    return DEFAULT_TTL_SECS


# ─── transport ────────────────────────────────────────────────────────────────


def default_transport(url, headers):
    """Perform an HTTP GET. Returns (status, header_dict, body_bytes)."""
    request = urllib.request.Request(url, headers=headers or {}, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            return response.status, dict(response.headers), response.read()
    except urllib.error.HTTPError as exc:  # 4xx / 5xx still carry a body
        try:
            body = exc.read()
        except Exception:
            body = b""
        return exc.code, dict(exc.headers or {}), body


class FixtureTransport:
    """Offline transport: reads recorded responses from a fixture directory."""

    def __init__(self, fixture_dir):
        self.dir = Path(fixture_dir)
        if not self.dir.is_dir():
            raise ConfigError("Fixture directory not found: %s" % self.dir)

    def get(self, path, params):
        for name in self._candidate_names(path, params):
            candidate = self.dir / name
            if candidate.is_file():
                try:
                    payload = json.loads(candidate.read_text(encoding="utf-8"))
                except (OSError, ValueError) as exc:
                    raise AAError("Cannot read fixture %s: %s" % (candidate, exc))
                return 200, {}, json.dumps(payload)
        raise AAError(
            "No fixture for path %r in %s (offline mode makes zero HTTP requests)"
            % (path, self.dir)
        )

    # Recorded fixture file names used by the ticket's research capture.
    KNOWN = {
        "data/llms/models": "legacy_models.json",
        "language/models/free": "v2_free.json",
        "media/text-to-image/models/free": "media_text_to_image_free.json",
        "media/speech-to-text/models/free": "media_speech_to_text_free.json",
        "media/image-editing/models/free": "media_image_editing_free.json",
        "media/text-to-video/models/free": "media_text_to_video_free.json",
        "media/image-to-video/models/free": "media_image_to_video_free.json",
        "media/music/instrumental/models/free": "media_music_instrumental_free.json",
        "media/music/vocal/models/free": "media_music_vocal_free.json",
        "media/speech-to-speech/models/free": "media_speech_to_speech_free.json",
    }

    @staticmethod
    def _candidate_names(path, params=None):
        clean = path.strip("/")
        flat = re.sub(r"[^a-z0-9]+", "_", clean.lower()).strip("_")
        names = ["%s.json" % flat]
        known = FixtureTransport.KNOWN.get(clean)
        if known:
            names.append(known)
        if clean == LEGACY_MODELS_PATH.strip("/"):
            names.append("legacy_models.json")
        elif clean == V2_FREE_MODELS_PATH.strip("/"):
            page = (params or {}).get("page")
            if page:
                names = ["v2_free_page%s.json" % page] + names
            names.append("v2_free.json")
        return names


# ─── client ───────────────────────────────────────────────────────────────────


class Client:
    """Tiny API client with a JSON-file cache and an injectable transport."""

    def __init__(self, cache_dir=DEFAULT_CACHE_DIR, ttl=None, refresh=False,
                 fixture_dir=None, transport=None, api_key=None,
                 now=time.time, stderr=None):
        if cache_dir is None:
            cache_dir = DEFAULT_CACHE_DIR
        self.cache_dir = Path(os.path.expanduser(str(cache_dir)))
        self.ttl = resolve_ttl() if ttl is None else ttl
        self.refresh = refresh
        self.now = now
        self.stderr = stderr or sys.stderr
        self.rate_limit_remaining = None
        if fixture_dir is not None:
            self.fixture_dir = Path(os.path.expanduser(str(fixture_dir)))
            self.transport = FixtureTransport(self.fixture_dir)
            self.api_key = None
        else:
            self.fixture_dir = None
            self.transport = transport or default_transport
            self.api_key = api_key if api_key is not None else resolve_api_key()

    # -- low level ----------------------------------------------------------

    def _cache_file(self, path, params):
        key = path + "?" + urllib.parse.urlencode(sorted((params or {}).items()))
        safe = re.sub(r"[^a-z0-9]+", "_", key.lower()).strip("_")
        return self.cache_dir / ("%s.json" % safe[:150])

    def get_json(self, path, params=None):
        """GET `path` (under /api/v2) and return the parsed JSON body."""
        if self.fixture_dir is not None:
            status, headers, body = self.transport.get(path, params)
        else:
            cache_file = self._cache_file(path, params)
            cached = None if self.refresh else self._read_cache(cache_file)
            if cached is not None:
                return cached
            url = API_BASE + path
            if params:
                url = "%s?%s" % (url, urllib.parse.urlencode(params))
            headers = {"x-api-key": self.api_key, "accept": "application/json"}
            status, resp_headers, body = self.transport(url, headers)
            remaining = self._header(resp_headers, "X-RateLimit-Remaining")
            if remaining is not None:
                self.rate_limit_remaining = remaining
                self.stderr.write("AA rate limit remaining: %s\n" % remaining)
            if status == 429:
                raise RateLimited(self._header(resp_headers, "Retry-After"))
            if status != 200:
                raise AAError("HTTP %s from %s — %s" % (status, path, _brief(body)))
            payload = _load_json(body, path)
            self._write_cache(cache_file, payload)
            return payload
        if status != 200:
            raise AAError("HTTP %s from %s — %s" % (status, path, _brief(body)))
        return _load_json(body, path)

    @staticmethod
    def _header(headers, name):
        if not headers:
            return None
        for key, value in headers.items():
            if str(key).lower() == name.lower():
                return value
        return None

    def _read_cache(self, cache_file):
        try:
            raw = json.loads(cache_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        if not isinstance(raw, dict) or "cached_at" not in raw:
            return None
        age = self.now() - float(raw["cached_at"])
        if age > self.ttl:
            return None
        return raw.get("data")

    def _write_cache(self, cache_file, payload):
        try:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            cache_file.write_text(
                json.dumps({"cached_at": self.now(), "data": payload}),
                encoding="utf-8",
            )
        except OSError as exc:
            sys.stderr.write("Warning: could not write cache: %s\n" % exc)

    # -- dataset ------------------------------------------------------------

    def load_models(self):
        """Joined model list from the legacy and free-v2 endpoints (join on id)."""
        legacy = self._endpoint_payload(LEGACY_MODELS_PATH)
        v2_pages = self._v2_pages()
        v2 = []
        version = None
        for page in v2_pages:
            if isinstance(page, dict):
                version = page.get("intelligence_index_version") or version
                v2.extend(page.get("data") or [])
            elif isinstance(page, list):
                v2.extend(page)

        joined = {}
        for record in legacy:
            model = _normalize_legacy(record)
            if model:
                joined.setdefault(model["id"], model)
        for record in v2:
            model = _normalize_v2(record)
            if not model:
                continue
            current = joined.get(model["id"])
            if current is None:
                joined[model["id"]] = model
            else:
                _merge(current, model)
        models = annotate_open_weights(list(joined.values()), load_overrides())
        return {"models": models, "intelligence_index_version": version}

    def _endpoint_payload(self, path, params=None):
        payload = self.get_json(path, params)
        if isinstance(payload, dict):
            return payload.get("data") or []
        if isinstance(payload, list):
            return payload
        raise AAError("Unexpected response shape from %s" % path)

    def _v2_pages(self):
        if self.fixture_dir is not None:
            pages = []
            for name in sorted(
                (p.name for p in self.fixture_dir.glob("v2_free_page*.json")),
                key=lambda n: int((re.search(r"(\d+)", n) or [0, 0])[1]),
            ):
                payload = json.loads((self.fixture_dir / name).read_text(encoding="utf-8"))
                pages.append(payload)
            if pages:
                return pages
        collected = []
        page_no = 1
        while True:
            payload = self.get_json(V2_FREE_MODELS_PATH, {"page": page_no})
            collected.append(payload)
            pagination = payload.get("pagination") if isinstance(payload, dict) else None
            if not pagination or not pagination.get("has_more"):
                break
            page_no += 1
            if page_no > 50:  # defensive: never spin on a malformed pagination block
                break
        return collected


def _load_json(body, path):
    if isinstance(body, (bytes, bytearray)):
        body = body.decode("utf-8", "replace")
    try:
        return json.loads(body)
    except ValueError:
        raise AAError("Response from %s is not valid JSON" % path)


def _brief(body, limit=200):
    if isinstance(body, (bytes, bytearray)):
        body = body.decode("utf-8", "replace")
    text = " ".join((body or "").split())
    return text[:limit] or "(empty body)"


def _num(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


def _creator_name(record):
    creator = record.get("model_creator")
    if isinstance(creator, dict):
        return creator.get("name") or ""
    return creator or ""


def _normalize_legacy(record):
    if not isinstance(record, dict) or not record.get("id"):
        return None
    ev = record.get("evaluations") or {}
    pricing = record.get("pricing") or {}
    model = {
        "id": record["id"],
        "name": record.get("name") or "",
        "slug": record.get("slug") or "",
        "creator": _creator_name(record),
        "release_date": record.get("release_date"),
        "intelligence": _num(ev.get("artificial_analysis_intelligence_index")),
        "coding": _num(ev.get("artificial_analysis_coding_index")),
        "math": _num(ev.get("artificial_analysis_math_index")),
        "agentic": None,
        "capabilities": {},
        "benchmarks": {key: _num(ev.get(key)) for key, _ in BENCHMARK_LABELS},
        "price_in": _num(pricing.get("price_1m_input_tokens")),
        "price_out": _num(pricing.get("price_1m_output_tokens")),
        "price_blended": _num(pricing.get("price_1m_blended_3_to_1")),
        "tok_per_s": _num(record.get("median_output_tokens_per_second")),
        "ttft": _num(record.get("median_time_to_first_token_seconds")),
        "ttft_answer": _num(record.get("median_time_to_first_answer_token")),
        "sources": ["legacy"],
    }
    return model


def _normalize_v2(record):
    if not isinstance(record, dict) or not record.get("id"):
        return None
    ev = record.get("evaluations") or {}
    pricing = record.get("pricing") or {}
    perf = record.get("performance") or {}
    capabilities = {}
    for suffix, _label in CAPABILITY_LABELS:
        value = _num(ev.get("artificial_analysis_%s_index" % suffix))
        if value is not None:
            capabilities[suffix] = value
    return {
        "id": record["id"],
        "name": record.get("name") or "",
        "slug": record.get("slug") or "",
        "creator": _creator_name(record),
        "release_date": record.get("release_date"),
        "intelligence": _num(ev.get("artificial_analysis_intelligence_index")),
        "coding": _num(ev.get("artificial_analysis_coding_index")),
        "math": None,
        "agentic": _num(ev.get("artificial_analysis_agentic_index")),
        "capabilities": capabilities,
        "benchmarks": {},
        "price_in": _num(pricing.get("price_1m_input_tokens")),
        "price_out": _num(pricing.get("price_1m_output_tokens")),
        "price_blended": None,
        "tok_per_s": _num(perf.get("median_output_tokens_per_second")),
        "ttft": _num(perf.get("median_time_to_first_token_seconds")),
        "ttft_answer": _num(perf.get("median_time_to_first_answer_token_seconds")),
        "sources": ["v2-free"],
    }


def _merge(target, extra):
    """Fill gaps in `target` from `extra` (legacy wins for shared fields)."""
    for key, value in extra.items():
        if key in ("sources", "capabilities", "benchmarks"):
            continue
        if target.get(key) in (None, "") and value not in (None, ""):
            target[key] = value
    for suffix, value in (extra.get("capabilities") or {}).items():
        target.setdefault("capabilities", {})[suffix] = value
    for key, value in (extra.get("benchmarks") or {}).items():
        if value is not None:
            target.setdefault("benchmarks", {})[key] = value
    target["sources"] = sorted(set(target.get("sources", [])) | set(extra.get("sources", [])))


# ─── formatting helpers ───────────────────────────────────────────────────────


def fmt(value, digits=1, dash="-"):
    if value is None:
        return dash
    if isinstance(value, str):
        return value
    return ("%." + str(digits) + "f") % value


def print_table(headers, rows, out=None):
    out = out or sys.stdout
    rows = [[str(cell) for cell in row] for row in rows]
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            if i < len(widths):
                widths[i] = max(widths[i], len(cell))
    line = "  ".join(h.ljust(widths[i]) for i, h in enumerate(headers))
    out.write(line.rstrip() + "\n")
    out.write("  ".join("-" * w for w in widths) + "\n")
    for row in rows:
        out.write("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)).rstrip() + "\n")


def attribution(version):
    if version:
        return "%s (Intelligence Index v%s)" % (ATTRIBUTION_BASE, version)
    return ATTRIBUTION_BASE


# ─── open-weights heuristic ───────────────────────────────────────────────────


def load_overrides(path=None):
    path = Path(path or OVERRIDES_PATH)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"include": [], "exclude": [], "params": {}}
    except (OSError, ValueError) as exc:
        sys.stderr.write("Warning: ignoring unreadable overrides %s: %s\n" % (path, exc))
        return {"include": [], "exclude": [], "params": {}}
    if not isinstance(data, dict):
        return {"include": [], "exclude": [], "params": {}}
    return {
        "include": data.get("include") or [],
        "exclude": data.get("exclude") or [],
        "params": data.get("params") or {},
    }


def looks_open_weights(name, overrides):
    """Override table first, then the curated open-weights family list."""
    lower = (name or "").lower()
    for needle in overrides.get("exclude") or []:
        if needle and needle.lower() in lower:
            return False
    for needle in overrides.get("include") or []:
        if needle and needle.lower() in lower:
            return True
    return any(family in lower for family in OPEN_WEIGHT_FAMILIES)


# Parameter counts embedded in model names. Rules, learned the hard way against live data:
#  * the number must be GLUED to its unit. "Nemotron 3.5 Bolt 74B-A9B" is version 3.5 of a
#    74B model, not 3.5B; "Qwen3-235B" is 235B, "Qwen3.8" carries no size at all.
#  * "T" is trillion, not billion: "Qwen3.8 2.4T A95B" is 2400B total / 95B active.
#  * a size token that directly follows a letter belongs to that token, so the "95B" inside
#    "A95B" is an active count, never a total.
#  * when the name has both a size and an active marker, the total is the size token that
#    sits immediately before the active marker ("74B-A9B", "397B A17B").
# Anything that does not match is unknown size — callers must exclude it unless --all asked
# for it, never treat it as small.
SIZE_TOKEN_RE = re.compile(
    r"(?<![A-Za-z0-9.])(?P<count>\d+(?:\.\d+)?)(?P<unit>[BT])(?![A-Za-z0-9])",
    re.IGNORECASE,
)
# MoE active-parameter marker: "-A22B", " A95B", "-A 3B".
ACTIVE_TOKEN_RE = re.compile(
    r"(?<![A-Za-z0-9])A\s*(?P<count>\d+(?:\.\d+)?)B(?![A-Za-z0-9])",
    re.IGNORECASE,
)
UNITS_TO_BILLIONS = {"b": 1.0, "t": 1000.0}


def parse_params(name):
    """Extract (total_b, active_b) in billions from names like '32B', '2.4T' or '235B-A22B'."""
    text = name or ""
    active, active_start = None, None
    active_match = ACTIVE_TOKEN_RE.search(text)
    if active_match:
        active = float(active_match.group("count"))
        active_start = active_match.start()
    sizes = [
        (match.start(), float(match.group("count")) * UNITS_TO_BILLIONS[match.group("unit").lower()])
        for match in SIZE_TOKEN_RE.finditer(text)
    ]
    total = None
    if active_start is not None:
        before = [item for item in sizes if item[0] < active_start]
        if before:
            total = before[-1][1]
    elif sizes:
        total = sizes[0][1]
    if total is None:
        return None, None
    if active is not None and active > total:
        # Contradictory naming (active > total): not confident, treat as unknown size.
        return None, None
    return total, (active if active is not None else total)


def override_params(model, overrides):
    table = overrides.get("params") or {}
    entry = table.get(model.get("slug") or "") or table.get(model.get("name") or "")
    if not isinstance(entry, dict):
        return None, None
    return _num(entry.get("total_b")), _num(entry.get("active_b"))


def weight_memory_gb(total_b, quant):
    return total_b * QUANT_BYTES_PER_PARAM[quant] * WEIGHT_MEMORY_OVERHEAD


def annotate_open_weights(models, overrides):
    """Attach open-weights flag and parameter estimates to each model."""
    for model in models:
        model["open_weights"] = looks_open_weights(model.get("name"), overrides)
        total, active = override_params(model, overrides)
        if total is None:
            total, active = parse_params(model.get("name"))
        model["total_b"] = total
        model["active_b"] = active
    return models


# ─── subcommands ──────────────────────────────────────────────────────────────


SORT_KEYS = {
    "intel": ("intelligence", True),
    "coding": ("coding", True),
    "agentic": ("agentic", True),
    "speed": ("tok_per_s", True),
    "price": ("price_blended", False),
    "release": ("release_date", True),
}


def _sort_models(models, sort):
    field, descending = SORT_KEYS[sort]
    if field == "release_date":
        return sorted(models, key=lambda m: (m.get("release_date") or "0000-00-00",
                                            m.get("intelligence") or -1),
                      reverse=descending)
    return sorted(models, key=lambda m: (m.get(field) is None, -(m.get(field) or 0) if descending else (m.get(field) or 0)))


def _model_fields(m):
    return {
        "id": m["id"],
        "name": m["name"],
        "slug": m["slug"],
        "creator": m["creator"],
        "release_date": m["release_date"],
        "intelligence_index": m["intelligence"],
        "coding_index": m["coding"],
        "agentic_index": m["agentic"],
        "capability_indexes": m.get("capabilities") or {},
        "benchmarks": m.get("benchmarks") or {},
        "price_1m_input": m["price_in"],
        "price_1m_output": m["price_out"],
        "price_1m_blended_3_to_1": m["price_blended"],
        "median_output_tokens_per_second": m["tok_per_s"],
        "median_time_to_first_token_seconds": m["ttft"],
        "open_weights": m.get("open_weights"),
        "total_params_b": m.get("total_b"),
        "active_params_b": m.get("active_b"),
        "sources": m.get("sources", []),
    }


def cmd_models(client, args):
    data = client.load_models()
    models = data["models"]
    if args.creator:
        needle = args.creator.lower()
        models = [m for m in models if needle in (m.get("creator") or "").lower()
                  or needle in (m.get("name") or "").lower()]
    if args.min_intel is not None:
        models = [m for m in models if (m.get("intelligence") or -1) >= args.min_intel]
    if args.since:
        models = [m for m in models if (m.get("release_date") or "") >= args.since]
    models = _sort_models(models, args.sort)
    total = len(models)
    models = models[: args.limit]
    if args.json:
        print(json.dumps({"models": [_model_fields(m) for m in models],
                          "matched": total,
                          "intelligence_index_version": data["intelligence_index_version"]},
                         indent=2))
        return 0
    rows = [
        [
            m["name"][:44], m["creator"][:16], fmt(m["intelligence"]),
            fmt(m["coding"]), fmt(m["agentic"]), fmt(m["tok_per_s"]),
            fmt(m["price_out"], 2), m["release_date"] or "-",
        ]
        for m in models
    ]
    print_table(
        ["MODEL", "CREATOR", "INTEL", "CODING", "AGENTIC", "TOK/S", "$/1M OUT", "RELEASED"],
        rows,
    )
    print("\n%d of %d models shown (sorted by %s)" % (len(rows), total, args.sort))
    print(attribution(data["intelligence_index_version"]))
    return 0


def _resolve_slug(models, needle):
    lower = needle.lower()
    for model in models:
        if (model.get("slug") or "").lower() == lower:
            return model
    for model in models:
        if (model.get("name") or "").lower() == lower or (model.get("id") or "").lower() == lower:
            return model
    names = ["%s|%s" % (m.get("slug") or "", m.get("name") or "") for m in models]
    pretty = [s.split("|", 1)[0] for s in difflib.get_close_matches(lower, names, n=5, cutoff=0.2)]
    if not pretty:
        pretty = [m.get("slug") or m.get("name") for m in models[:5]]
    raise AAError("Unknown model %r. Did you mean: %s" % (needle, ", ".join(pretty)))


def cmd_compare(client, args):
    data = client.load_models()
    models = [_resolve_slug(data["models"], slug) for slug in args.slugs]
    if args.json:
        print(json.dumps({"models": [_model_fields(m) for m in models],
                          "intelligence_index_version": data["intelligence_index_version"]},
                         indent=2))
        return 0
    metrics = [
        ("Creator", lambda m: m["creator"] or "-"),
        ("Released", lambda m: m["release_date"] or "-"),
        ("Intelligence Index", lambda m: fmt(m["intelligence"])),
        ("Coding Index", lambda m: fmt(m["coding"])),
        ("Agentic Index", lambda m: fmt(m["agentic"])),
    ]
    for suffix, label in CAPABILITY_LABELS:
        metrics.append((label, lambda m, s=suffix: fmt((m.get("capabilities") or {}).get(s))))
    for key, label in BENCHMARK_LABELS:
        metrics.append(("%s (0-1)" % label, lambda m, k=key: fmt((m.get("benchmarks") or {}).get(k), 3)))
    metrics += [
        ("$/1M input", lambda m: fmt(m["price_in"], 2)),
        ("$/1M output", lambda m: fmt(m["price_out"], 2)),
        ("$/1M blended (3:1)", lambda m: fmt(m["price_blended"], 2)),
        ("Median tokens/s", lambda m: fmt(m["tok_per_s"])),
        ("Median TTFT (s)", lambda m: fmt(m["ttft"], 2)),
        ("Open weights", lambda m: "yes" if m.get("open_weights") else "no"),
    ]
    headers = ["METRIC"] + [m["name"][:34] for m in models]
    rows = [[label] + [getter(m) for m in models] for label, getter in metrics]
    print_table(headers, rows)
    print()
    print(attribution(data["intelligence_index_version"]))
    return 0


def cmd_search(client, args):
    data = client.load_models()
    needle = args.text.lower()
    matches = [
        m for m in data["models"]
        if needle in (m.get("name") or "").lower() or needle in (m.get("creator") or "").lower()
    ]
    matches = _sort_models(matches, "intel")
    if args.json:
        print(json.dumps({"query": args.text, "models": [_model_fields(m) for m in matches]}, indent=2))
        return 0
    print_table(
        ["MODEL", "CREATOR", "INTEL", "RELEASED"],
        [[m["name"][:44], m["creator"][:18], fmt(m["intelligence"]), m["release_date"] or "-"]
         for m in matches],
    )
    print("\n%d models match %r" % (len(matches), args.text))
    print(attribution(data["intelligence_index_version"]))
    return 0


def cmd_open_weights(client, args):
    overrides = load_overrides()
    data = client.load_models()
    models = annotate_open_weights(data["models"], overrides)
    candidates = [m for m in models if m["open_weights"]]
    excluded_closed = len(models) - len(candidates)
    rows, kept = [], []
    for model in candidates:
        if model.get("total_b") is None and not args.all:
            continue
        kept.append(model)
    kept = _sort_models(kept, "intel")[: args.limit]
    for model in kept:
        total = model.get("total_b")
        if total is None:
            weight, fits = None, "unknown"
        elif not args.ram:
            weight, fits = weight_memory_gb(total, args.quant), "-"
        else:
            weight = weight_memory_gb(total, args.quant)
            fits = "yes" if weight <= args.ram else "no"
        rows.append([
            model["name"][:42],
            model["creator"][:14],
            fmt(total, 1),
            fmt(model.get("active_b"), 1),
            fmt(model["intelligence"]),
            fmt(weight, 1),
            fits,
        ])
    if args.json:
        print(json.dumps({
            "quant": args.quant,
            "ram_gb": args.ram,
            "excluded_closed_weight": excluded_closed,
            "models": [dict(_model_fields(m), total_params_b=m.get("total_b"),
                            active_params_b=m.get("active_b"),
                            est_weight_memory_gb=(
                                weight_memory_gb(m["total_b"], args.quant)
                                if m.get("total_b") is not None else None),
                            fits=(m.get("total_b") is not None and m["total_b"]
                                  * QUANT_BYTES_PER_PARAM[args.quant] * WEIGHT_MEMORY_OVERHEAD <= (args.ram or 0)))
                        for m in kept],
        }, indent=2))
        return 0
    headers = ["MODEL", "CREATOR", "TOTAL B", "ACTIVE B", "INTEL", "EST WEIGHT GB", "FITS"]
    if not args.ram:
        headers[6] = "FITS (--ram needed)"
    print_table(headers, rows)
    print("\nEstimate: total params x bytes/param (%s = %.2f) + %d%% overhead."
          % (args.quant, QUANT_BYTES_PER_PARAM[args.quant], int((WEIGHT_MEMORY_OVERHEAD - 1) * 100)))
    print("Estimate only — KV cache, activation memory and context length are NOT modelled; budget 10-30 % extra.")
    if args.ram:
        print("Fits compared against %g GB usable memory. %d closed-weight model(s) excluded."
              % (args.ram, excluded_closed))
    else:
        print("%d closed-weight model(s) excluded." % excluded_closed)
    print(attribution(data["intelligence_index_version"]))
    return 0


def cmd_raw(client, args):
    path = args.path.strip()
    path = re.sub(r"^https?://[^/]+", "", path)
    path = re.sub(r"^/?api/v2", "", path)
    if not path.startswith("/"):
        path = "/" + path
    if ".." in path:
        raise AAError("Refusing path traversal in %r" % args.path)
    params = {}
    for item in args.param or []:
        if "=" not in item:
            raise AAError("--param expects key=value, got %r" % item)
        key, _, value = item.partition("=")
        params[key.strip()] = value
    payload = client.get_json(path, params or None)
    print(json.dumps(payload, indent=2, sort_keys=False))
    return 0


# ─── CLI wiring ───────────────────────────────────────────────────────────────


def build_parser():
    # Global flags. They are accepted before AND after the subcommand; SUPPRESS keeps the
    # subparser default from clobbering a value already parsed by the main parser.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--cache-dir", default=argparse.SUPPRESS,
                        help="Cache directory (default: %s)" % DEFAULT_CACHE_DIR)
    common.add_argument("--refresh", action="store_true", default=argparse.SUPPRESS,
                        help="Ignore the cache and hit the API")
    common.add_argument("--fixture-dir", default=argparse.SUPPRESS,
                        help="Offline mode: read recorded responses from DIR, zero HTTP")
    common.add_argument("--json", action="store_true", default=argparse.SUPPRESS,
                        help="Print JSON instead of a table")

    parser = argparse.ArgumentParser(
        prog="aa.py",
        description="Artificial Analysis Data API client: model comparison, ranking and "
                    "open-weights hardware fit. Data: artificialanalysis.ai",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Examples:\n"
               "  aa.py models --min-intel 20 --limit 10\n"
               "  aa.py compare gpt-6-astra-xhigh claude-opus-5-5\n"
               "  aa.py search qwen\n"
               "  aa.py open-weights --ram 120 --quant q4_k_m\n"
               "  aa.py raw media/text-to-image/models/free\n",
    )
    # globals accepted before the subcommand
    parser.add_argument("--cache-dir", default=argparse.SUPPRESS)
    parser.add_argument("--refresh", action="store_true", default=argparse.SUPPRESS)
    parser.add_argument("--fixture-dir", default=argparse.SUPPRESS)
    parser.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
    sub = parser.add_subparsers(dest="command", required=True, parser_class=argparse.ArgumentParser)

    models = sub.add_parser("models", parents=[common], help="List/rank models from the joined catalog")
    models.add_argument("--creator", metavar="SUBSTR", help="Filter by creator or model name substring")
    models.add_argument("--min-intel", type=float, metavar="N", help="Minimum intelligence index")
    models.add_argument("--since", metavar="YYYY-MM-DD", help="Only models released on/after this date")
    models.add_argument("--sort", choices=sorted(SORT_KEYS), default="intel",
                        help="Sort key (default: intel, descending)")
    models.add_argument("--limit", type=int, default=25, help="Max rows (default 25)")
    models.set_defaults(func=cmd_models)

    compare = sub.add_parser("compare", parents=[common], help="Side-by-side comparison of models")
    compare.add_argument("slugs", nargs="+", metavar="SLUG", help="Model slug (or exact name)")
    compare.set_defaults(func=cmd_compare)

    search = sub.add_parser("search", parents=[common], help="Substring search over name + creator")
    search.add_argument("text", metavar="TEXT")
    search.set_defaults(func=cmd_search)

    open_weights = sub.add_parser("open-weights", parents=[common],
                                  help="Open-weights models, optionally filtered by RAM budget")
    open_weights.add_argument("--ram", type=float, metavar="GB",
                              help="Usable memory in GB (e.g. 120 on a 128 GB Strix Halo)")
    open_weights.add_argument("--quant", choices=sorted(QUANT_BYTES_PER_PARAM), default="q4_k_m",
                              help="Quantisation to estimate weight memory for (default q4_k_m)")
    open_weights.add_argument("--limit", type=int, default=25, help="Max rows (default 25)")
    open_weights.add_argument("--all", action="store_true",
                              help="Also list models whose parameter count is unknown")
    open_weights.set_defaults(func=cmd_open_weights)

    raw = sub.add_parser("raw", parents=[common], help="GET any path under /api/v2 and print JSON")
    raw.add_argument("path", metavar="PATH", help="e.g. media/text-to-video/models/free")
    raw.add_argument("--param", action="append", metavar="K=V", help="Query parameter (repeatable)")
    raw.set_defaults(func=cmd_raw)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    defaults = {"cache_dir": DEFAULT_CACHE_DIR, "refresh": False, "fixture_dir": None, "json": False}
    for key, value in defaults.items():
        if not hasattr(args, key):
            setattr(args, key, value)
    try:
        client = Client(cache_dir=args.cache_dir, refresh=args.refresh, fixture_dir=args.fixture_dir)
        return args.func(client, args)
    except ConfigError as exc:
        # Ticket contract: a missing key is exit 1, other failures are exit 2.
        sys.stderr.write("error: %s\n" % exc)
        return 1
    except AAError as exc:
        sys.stderr.write("error: %s\n" % exc)
        return 2
    except BrokenPipeError:
        return 0


if __name__ == "__main__":
    sys.exit(main())
