#!/usr/bin/env python3
"""say.py — turn text into speech on the local TTS server and play it.

One command does the whole round trip: health check, (re-)register voices if the
server's voice list is empty, synthesize a WAV, then play it.

  echo "hello" | say.py
  say.py -t "short message"
  say.py -f notes.txt --no-play -o /tmp/reply.wav
  say.py --status

Config: see config/tts-conversation.example.json. Resolution order:
  --config  >  $TTS_CONVERSATION_CONFIG  >  ~/.config/tts-conversation/config.json
  >  <skill>/config/tts-conversation.json
"""
from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tts_config  # noqa: E402


def prune(out_dir: Path, keep: int) -> None:
    if keep <= 0 or not out_dir.is_dir():
        return
    files = sorted(out_dir.glob("say-*.wav"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in files[keep:]:
        old.unlink(missing_ok=True)


def main() -> None:
    ap = argparse.ArgumentParser(description="synthesize text to speech and play it")
    src = ap.add_mutually_exclusive_group()
    src.add_argument("-t", "--text", help="text to speak")
    src.add_argument("-f", "--file", help="read text from a file")
    ap.add_argument("-o", "--out", help="output WAV path (default: <out_dir>/say-<epoch>.wav)")
    ap.add_argument("--voice", help="registered voice name (default: from config)")
    ap.add_argument("--language", help="language label, e.g. English, German")
    ap.add_argument("--seed", type=int, help="reproducible synthesis seed")
    ap.add_argument("--config", help="path to config JSON")
    ap.add_argument("--register", action="store_true", help="force voice re-registration first")
    play = ap.add_mutually_exclusive_group()
    play.add_argument("--play", dest="play", action="store_true", default=None, help="always play")
    play.add_argument("--no-play", dest="play", action="store_false", help="write the file only")
    ap.add_argument("--status", action="store_true", help="print resolved config and API health, then exit")
    args = ap.parse_args()

    cfg, cfg_path = tts_config.load(args.config)
    if args.language:
        cfg["language"] = args.language
    if args.seed is not None:
        cfg["seed"] = args.seed

    if args.status:
        print(f"config : {cfg_path or 'none (built-in defaults)'}")
        print(f"server : {cfg['server']}  health={'ok' if tts_config.health(cfg) else 'DOWN'}")
        print(f"voices : {', '.join(tts_config.list_voices(cfg)) or 'none registered'}")
        print(f"voice  : {cfg.get('voice') or '<default>'}   language: {cfg['language']}")
        print(f"player : {cfg['player']}   out_dir: {cfg['out_dir']}   voices_dir: {cfg.get('voices_dir')}")
        return

    if args.text:
        text = args.text
    elif args.file:
        text = Path(args.file).expanduser().read_text(encoding="utf-8")
    elif not sys.stdin.isatty():
        text = sys.stdin.read()
    else:
        ap.error("nothing to say: use -t, -f, or stdin")

    text = text.strip()
    if not text:
        raise SystemExit("nothing to synthesize (empty text)")

    if not tts_config.health(cfg):
        raise SystemExit(f"TTS API not reachable at {cfg['server']} — is the service running? "
                         "(see SKILL.md for the server's setup/health commands)")

    if args.register:
        tts_config.register_voices(cfg)
    elif cfg.get("voices_dir") and not tts_config.list_voices(cfg):
        added = tts_config.register_voices(cfg)
        if added:
            print(f"registered voices: {', '.join(added)}", file=sys.stderr)

    if args.out:
        out_file = Path(args.out).expanduser()
    else:
        out_dir = Path(cfg["out_dir"]).expanduser()
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = out_dir / f"say-{int(time.time())}.wav"

    tts_config.synthesize(cfg, text, out_file, voice=args.voice)
    prune(Path(cfg["out_dir"]).expanduser(), int(cfg.get("keep_files", 0)))

    do_play = cfg.get("auto_play", True) if args.play is None else args.play
    if do_play:
        cmd = tts_config.player_cmd(cfg, out_file)
        if cmd is None:
            print("warning: no audio player found; file written only", file=sys.stderr)
        else:
            import subprocess

            print(f"playing {out_file}", file=sys.stderr)
            subprocess.run(cmd, check=False)
    print(out_file)


if __name__ == "__main__":
    main()
