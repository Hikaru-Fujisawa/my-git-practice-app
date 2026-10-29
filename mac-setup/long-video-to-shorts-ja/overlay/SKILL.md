---
name: long-video-to-shorts
description: 'Turn ONE long video into several vertical (9:16) captioned shorts, fully local and free — a home-made Opus Clip. Japanese by default. Use when the user wants 「この動画からショートを作って」「切り抜き動画を作って」「縦型の字幕付きクリップにして」「いいところを抜き出して」, "make shorts / reels / tiktok clips from this video", or names Opus Clip / Klap / Vizard and wants it done locally. Flow: propose candidates → the user picks → render 9:16 MP4s with burned-in Japanese captions. Never uploads or posts anything.'
metadata:
  tags: shorts, clips, 切り抜き, 字幕, reframe, captions, ffmpeg, faster-whisper, 9:16, tiktok, reels, japanese
---

# long-video-to-shorts (日本語・ローカル版)

**One long video → N vertical captioned shorts, 100% local and free.** The agent
transcribes (faster-whisper on CPU), proposes the best moments, and — only after the
user picks — cuts, reframes to 9:16 (1080x1920), and burns in Japanese captions + a hook
title. See `DESIGN.md` for the original spec; this copy is adapted for Japanese on macOS.

## Hard rules

- **No cost.** Only local tools. Never call a paid/hosted API, never sign up for anything.
- **No publishing.** Never upload, post or schedule the shorts anywhere. Output = local MP4s.
- **No render before approval.** Stage 4 always stops and waits for the user's choice.
- **Always run steps through `scripts/lvs.sh`** — it loads `local.env` (dedicated Python
  venv, ffmpeg/node location, model cache) without touching the system Python/Node/PATH.
- Never caption fabricated words over silence (see Decision gate).

Below, `$SKILL` = this skill's directory (normally `~/.claude/skills/long-video-to-shorts`).

## Pipeline (6 stages)

Pick a **project dir**: `~/shorts-jobs/<name>/` (ASCII name, no spaces preferred).
All intermediates live in `<project>/work/`, finals in `<project>/shorts/`.

```
0. CHECK      bash $SKILL/scripts/lvs.sh check            (ffmpeg+libass, node, venv, font)
1. INTAKE     bash $SKILL/scripts/lvs.sh intake.sh <file> <project>        -> work/source.mp4
2. PROBE      bash $SKILL/scripts/lvs.sh probe.sh <project>                -> work/probe.json + work/contactsheet.png
              Read the contact sheet (60 frames across the whole video). Classify ranges: facecam or screen.
3. TRANSCRIBE bash $SKILL/scripts/lvs.sh transcribe <project>/work/source.mp4 <project>/work/transcript.json --lang ja --model small
              (--model medium = more accurate, ~3x slower. Tell the user the rough wait for long videos.)
4. PICK       Read references/highlight-selection.md + transcript.json (segments[] is easiest to read).
              Write <project>/work/clips.json (schema: clips.schema.json).
              ⏸  PRESENT the candidate table → WAIT for the user to choose (keep/drop/adjust).
5. BUILD      Only the chosen clips — see "Build a clip".
6. DELIVER    Write <project>/shorts/manifest.md (title, range, reason, hashtag ideas). Give the paths.
```

URL intake (`intake.sh <URL>`) needs `yt-dlp`, which is NOT installed by default. Prefer
local files; only use a URL if the user asks and confirms they have the right to download it.

## Stage 4 — candidate table (Japanese)

Show one row per candidate, numbered so the user can answer 「1と3」:

| # | 区間 | 長さ | 種類 | タイトル案（フック） | 選んだ理由 |
|---|---|---|---|---|---|

Japanese-specific selection rules (on top of `references/highlight-selection.md`):
- Snap to sentence ends (`。`, `？`, or a pause between `segments[]`), never mid-phrase.
- Hook titles: **≤ 18 full-width chars**, one accent phrase in `*asterisks*`,
  e.g. `再生数が*10倍*になった方法`. Wrapping/size is automatic (2 lines, shrinks to fit).
- Skip filler-heavy openings (「えー」「あのー」「まあ」) — start on the first content word.
- Each short 12–60s. List every candidate that holds up; the user trims.

## Build a clip (stage 5)

Same command for both content types; captions are burned in by libass:

```bash
bash $SKILL/scripts/lvs.sh build_clip.sh <project> \
  --start 00:04:12.0 --end 00:04:58.0 --kind facecam --face-cx 0.62 \
  --caption-mode ass --title "再生数が*10倍*になった方法" --hook true \
  --out <project>/shorts/01_slug.mp4
```

- `--kind facecam` → fixed 9:16 crop around the face. Set `--face-cx` by vision: grab a
  frame (`ffmpeg -ss <mid> -i work/source.mp4 -frames:v 1 f.png`), look, estimate the face's
  horizontal center 0..1 (see `references/reframe.md`).
- `--kind screen` → full frame over a blurred background (nothing cropped).
- **Always `--caption-mode ass`** here. (`embedded` needs a separate `embedded-captions`
  skill that is not installed.) `--caption-mode none` = no captions.
- `--style <name>` overrides the caption style per clip (see Customization).
- Output slug: ASCII is safest (`01_kotsu.mp4`); Japanese names also work.

After each build, verify: `ffprobe` says 1080x1920 with audio, and look at 1–2 frames
(`ffmpeg -ss 3 -i out.mp4 -frames:v 1 check.png`) — captions inside the frame, no tofu (□).

## Japanese captions — how they work

- Whisper outputs Japanese as sub-word pieces; `scripts/ja_text.cjs` rebuilds natural words
  with Node's built-in `Intl.Segmenter` and joins them **without spaces**.
- Lines are packed by **real width** (full-width = 1em) to stay inside `safe_zone`, break
  after `。`/`？`, after `、` when half full, at pauses, and preferably at phrase boundaries
  (after particles). Anything still too wide is scaled down — text never leaves the frame.
- Font: `assets/fonts/NotoSansJP-Bold.otf` (Noto Sans JP, SIL OFL 1.1 — free).
- Latin-only transcripts render exactly as upstream.

## Decision gate — refuse rather than ship garbage

Read `references/troubleshooting.md`. Skip / split when: near-silent audio (whisper
hallucinates 「ご視聴ありがとうございました」 over silence — drop those words), transcript
is gibberish (retry `--model medium`), source already has burned-in captions (use
`--caption-mode none`), or a facecam range has hard cuts / several speakers moving across
the frame (split it, or use `--kind screen`).

## Customization — `config.json`

- **`caption_style`** — `word-pop | capcut | clean | label | karaoke | one-word | boxed | bicolor`.
  For Japanese, `word-pop`, `karaoke`, `clean` read best. Override per clip: `--style`.
- **`accent_color` / `hook_accent_color`** — hex.
- **`font` / `font_family`** — must contain Japanese glyphs (default Noto Sans JP).
- **`hook_seconds`**, **`caption_pos_y`**, **`hook_pos_y`**, **`safe_zone`** — as upstream.

## Files

- `scripts/lvs.sh` — runner (reads `local.env`); `scripts/ja_text.cjs` — Japanese text helpers
- `scripts/` — `intake.sh`, `probe.sh`, `transcribe.py`, `cut.sh`, `reframe_facecam.sh`,
  `reframe_gameplay.sh`, `ass_from_words.cjs`, `captions_burn.sh`, `hook_ass.cjs`,
  `hook_title.sh`, `build_clip.sh`, `lib_config.cjs`
- `references/` — `highlight-selection.md`, `reframe.md`, `captions-gameplay.md`, `troubleshooting.md`
- `JA-MAC-NOTES.md` — what was changed from upstream and why
