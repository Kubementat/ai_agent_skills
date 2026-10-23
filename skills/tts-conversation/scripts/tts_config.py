#!/usr/bin/env python3
"""Config loading and OmniVoice API helpers for the tts-conversation skill.

Standard library only. No personal data lives in this file: everything
specific to a machine comes from the user config file.
"""
from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

DEFAULTS = {
    "server": "http://127.0.0.1:8977",
    "voice": None,            # omit => server default voice
    "language": "English",
    "instructions": None,     # voice-design style, closed vocabulary only
    "seed": None,
    "auto_play": True,
    "player": "auto",         # auto | paplay | pw-play | ffplay | <binary>
    "players": ["paplay", "pw-play", "ffplay", "aplay"],
    "out_dir": "~/.cache/tts-conversation",
    "keep_files": 20,
    "voices_dir": None,       # if set, (re-)register <name>.wav+<name>.txt from here
    "max_words": 90,
    "timeout_s": 900,
}

PLAYER_ARGS = {
    "paplay": None,                       # file
    "pw-play": None,                      # file
    "aplay": None,                        # file (WAV only)
    "ffplay": ["-nodisp", "-autoexit", "-loglevel", "quiet"],
}


def config_path(explicit: str | None = None) -> Path | None:
    """Return the first config file that exists, honouring --config and $TTS_CONVERSATION_CONFIG."""
    candidates = []
    if explicit:
        candidates.append(Path(explicit).expanduser())
    env = os.environ.get("TTS_CONVERSATION_CONFIG")
    if env:
        candidates.append(Path(env).expanduser())
    candidates.append(Path.home() / ".config" / "tts-conversation" / "config.json")
    candidates.append(Path(__file__).resolve().parent.parent / "config" / "tts-conversation.json")
    for path in candidates:
        if path.is_file():
            return path
    return None


def load(explicit: str | None = None) -> tuple[dict, Path | None]:
    cfg = dict(DEFAULTS)
    path = config_path(explicit)
    if path:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        for key, value in data.items():
            if key in DEFAULTS:
                cfg[key] = value
            else:
                print(f"warning: ignoring unknown config key {key!r}", file=sys.stderr)
    for key in ("server", "voice", "instructions", "out_dir", "voices_dir"):
        if isinstance(cfg.get(key), str):
            cfg[key] = cfg[key].strip().rstrip("/") if key == "server" else os.path.expanduser(cfg[key])
    return cfg, path


def _request(url: str, payload: dict | None = None, timeout: float = 30.0) -> tuple[int, bytes]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST" if payload is not None else "GET")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def health(cfg: dict) -> bool:
    try:
        code, body = _request(cfg["server"].rstrip("/") + "/health", timeout=5)
    except Exception:
        return False
    return code == 200 and b"ok" in body


def list_voices(cfg: dict) -> list[str]:
    code, body = _request(cfg["server"].rstrip("/") + "/v1/audio/voices")
    if code != 200:
        return []
    try:
        return [v["name"] for v in json.loads(body).get("voices", [])]
    except Exception:
        return []


def register_voices(cfg: dict) -> list[str]:
    """Register every <name>.wav + <name>.txt (or <name>.rvq) found in voices_dir."""
    voices_dir = cfg.get("voices_dir")
    if not voices_dir or not Path(voices_dir).is_dir():
        return []
    registered = []
    for ref in sorted(Path(voices_dir).glob("*")):
        if ref.suffix.lower() not in (".wav", ".rvq"):
            continue
        transcript = ref.with_suffix(".txt")
        if not transcript.is_file():
            print(f"warning: {ref.name}: missing {transcript.name}, skipping", file=sys.stderr)
            continue
        field = "wav_b64" if ref.suffix.lower() == ".wav" else "rvq_b64"
        payload = {
            "name": ref.stem,
            "ref_text": transcript.read_text(encoding="utf-8").strip(),
            field: base64.b64encode(ref.read_bytes()).decode("ascii"),
        }
        code, body = _request(cfg["server"].rstrip("/") + "/v1/audio/voices", payload, timeout=cfg["timeout_s"])
        if code == 200:
            registered.append(ref.stem)
        else:
            print(f"warning: registering {ref.stem} failed: {body[:200]!r}", file=sys.stderr)
    return registered


def synthesize(cfg: dict, text: str, out_file: Path, voice: str | None = None) -> Path:
    payload = {"input": text, "response_format": "wav"}
    v = voice if voice is not None else cfg.get("voice")
    if v:
        payload["voice"] = v
    if cfg.get("language"):
        payload["language"] = cfg["language"]
    if cfg.get("instructions") and not v:
        payload["instructions"] = cfg["instructions"]
    if cfg.get("seed") is not None:
        payload["seed"] = int(cfg["seed"])
    code, body = _request(cfg["server"].rstrip("/") + "/v1/audio/speech", payload, timeout=cfg["timeout_s"])
    if code != 200:
        try:
            detail = json.loads(body).get("error", {}).get("message", body.decode(errors="replace"))
        except Exception:
            detail = body.decode(errors="replace")
        raise SystemExit(f"synthesis failed (HTTP {code}): {detail}")
    out_file.parent.mkdir(parents=True, exist_ok=True)
    out_file.write_bytes(body)
    return out_file


def player_cmd(cfg: dict, path: Path) -> list[str] | None:
    """Resolve a command that plays a WAV file; None if nothing is available."""
    import shutil

    setting = cfg.get("player") or "auto"
    order = [setting] if setting != "auto" else list(cfg.get("players", PLAYER_ARGS.keys()))
    for name in order:
        binary = shutil.which(name)
        if not binary:
            continue
        if name == "ffplay":
            return [binary, *PLAYER_ARGS["ffplay"], str(path)]
        return [binary, str(path)]
    return None
