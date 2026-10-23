---
name: tts-conversation
description: >
  Talk instead of typing. Turns an agent turn into a short spoken reply by synthesizing
  it with the local TTS server and playing the WAV on the machine's speakers. Use when the
  user asks to "answer in speech", "speak that", "voice mode", "tts", "speech answer",
  "conversation instead of typing", asks for a voice reply, or asks to auto-play audio after
  generating it. Also use for follow-up turns in a conversation the user started by asking
  for audio.
---

# TTS Conversation Mode

Speak the answer instead of writing a wall of text. One command does the round trip:
health check, voice registration if needed, synthesize WAV, play it.

```bash
python3 {skill_dir}/scripts/say.py -t "the text you want spoken"
python3 {skill_dir}/scripts/say.py -f /tmp/reply.txt        # longer text from a file
echo "hello" | python3 {skill_dir}/scripts/say.py          # stdin
python3 {skill_dir}/scripts/say.py --status                 # server, voices, resolved config
python3 {skill_dir}/scripts/say.py -f notes.txt --no-play -o ./reply.wav
```

`{skill_dir}` is the directory holding this file. The script prints the output path on
stdout and progress/warnings on stderr, so it is safe to chain.

## How to talk (the actual point of this skill)

Spoken output is not text read aloud. A turn that looks fine on screen sounds terrible in
the ear, and long audio wastes the user's time. Rules, in order:

1. **Short.** One spoken idea per turn, staying under `max_words` from the config
   (default 90 ≈ 45 seconds of audio). A wall of text becomes a wall of audio.
2. **Ask at most one question per turn.** Two questions spoken back to back just get
   answered by whichever one you remember.
3. **Write for the ear.** No markdown, no bullets, no headings, no code fences, no
   backticks. Spell out things that would sound absurd read literally — a path becomes
   "the vault goals directory", a version becomes "one point four", a flag becomes its
   name. Short sentences. Second person. Present tense where possible.
4. **Say the number of choices out loud** ("two decisions, number one and number two"), so
   the listener knows the structure without scrolling.
5. **Prefer a file for the detail.** If the answer needs code, commands, or a table, say the
   conclusion out loud and write the detail to a file the user can open. Then name the file.
6. **Do not read the file back.** Generate the audio once, play it, and stop.

If the user's own voice or another registered voice matters to them, ask which one once and
put it in the config rather than asking every turn.

## Configuration

The skill ships with **no machine-specific settings**. All of it lives in a user config:

```bash
mkdir -p ~/.config/tts-conversation
cp {skill_dir}/config/tts-conversation.example.json ~/.config/tts-conversation/config.json
```

Resolution order: `--config` > `$TTS_CONVERSATION_CONFIG` >
`~/.config/tts-conversation/config.json` > `<skill_dir>/config/tts-conversation.json`.
A project can pin its own config by exporting `TTS_CONVERSATION_CONFIG`.

| Key | Default | Meaning |
|---|---|---|
| `server` | `http://127.0.0.1:8977` | TTS server base URL. Loopback — if the server runs on another host, tunnel it (SSH port forward) or point it at the LAN address |
| `voice` | `null` | registered voice name; `null` uses the server's default voice |
| `language` | `English` | one language per request; set it explicitly for non-English |
| `instructions` | `null` | voice-design style, only if `voice` is unset — closed vocabulary, see the TTS server's own skill |
| `auto_play` | `true` | play the file when done; `--no-play` overrides |
| `player` / `players` | `auto` | first available of paplay, pw-play, ffplay, aplay |
| `out_dir` / `keep_files` | `~/.cache/tts-conversation` / `20` | output location and how many clips to retain |
| `voices_dir` | `null` | directory holding `<name>.wav` + `<name>.txt` (or `.rvq`) reference files, auto-registered when the server's voice list is empty |
| `seed` | `null` | positive = reproducible voice |
| `max_words` | `90` | target length of a spoken turn |

Anything unknown in the config is reported and ignored, so old keys never break a run.

## Voice clones

Registered voices exist only in server memory and are **wiped on every service restart**.
Set `voices_dir` and the script re-registers automatically the first time it sees an empty
voice list; `--register` forces it. The reference WAV (or pre-encoded RVQ) lives next to a
`.txt` transcript of what the reference says — that transcript is required, and quality
depends on it. Keep reference audio out of this repo; `voices_dir` should point somewhere
private.

## Latency and failure notes

- Synthesis is **serialized** (single server context). One request at a time; never fire
  parallel or retry-storm requests.
- Rough cost: about one minute of audio per ~100 words, and compute time is usually *lower*
  than audio length (5 minutes of audio finished in ~3.5 minutes). Tell the user before a
  long clip, or cut the text.
- Output is WAV only — no MP3. Convert with `ffmpeg` if the user wants a smaller file to
  carry around.
- `server unreachable` / health failure: the TTS service is not running or not port-forwarded.
  `say.py --status` distinguishes "server down" from "no voices registered".
- Weird or wrong-accent speech: one language per request. Split mixed-language text and
  run two calls.
- No audio despite a good file: `--status` shows the resolved player; on headless boxes
  nothing will play, and the printed path is the deliverable.

## Public repo rule

Never put hostnames, IPs, usernames, absolute home paths, voice names, or any other
machine-specific value in this directory. Put them in the user config instead, and if a
question about the environment comes up, answer from `say.py --status` rather than guessing.
