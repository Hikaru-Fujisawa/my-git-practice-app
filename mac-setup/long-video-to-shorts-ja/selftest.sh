#!/usr/bin/env bash
# End-to-end self-test of the installed skill with Japanese speech (no real video needed).
# Creates a NEW job dir ~/shorts-jobs/_selftest-<timestamp>/ and never overwrites anything.
#
#   bash selftest.sh [--model small|medium]
#
# Speech source: macOS built-in Japanese voice (`say`, e.g. Kyoko) if installed, otherwise two
# ~3s public test clips from Hugging Face (japanese-asr datasets, sha256-checked).
set -euo pipefail
SKILL="${SKILL:-$HOME/.claude/skills/long-video-to-shorts}"
MODEL="small"; [ "${1:-}" = "--model" ] && MODEL="${2:?model}"
LVS="$SKILL/scripts/lvs.sh"
[ -x "$LVS" ] || [ -f "$LVS" ] || { echo "skill not installed at $SKILL"; exit 2; }
. "$SKILL/local.env"; export PATH="$LVS_PATH_PREFIX:$PATH"

JOB="$HOME/shorts-jobs/_selftest-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$JOB/input"
PASS=0; FAILS=0
res(){ if [ "$1" = 0 ]; then echo "  PASS  $2"; PASS=$((PASS+1)); else echo "  FAIL  $2"; FAILS=$((FAILS+1)); fi; }
# run <label> <cmd...>: record PASS/FAIL without letting `set -e` abort the summary
run(){ local label="$1"; shift; if "$@" >"$JOB/last.log" 2>&1; then res 0 "$label"; else res 1 "$label"; tail -5 "$JOB/last.log" | sed 's/^/        /'; fi; }

echo "== tools"; bash "$LVS" check

echo "== speech"
TEXT="今日は、ショート動画の再生回数を伸ばすコツを三つお話しします。一つ目は、最初の三秒で結論を言うことです。二つ目は、字幕を必ず入れることです。三つ目は、六十秒以内にまとめることです。"
VOICE="$(say -v '?' 2>/dev/null | awk '/ja_JP/{print $1; exit}' || true)"
if [ -n "$VOICE" ]; then
  say -v "$VOICE" -o "$JOB/input/speech.aiff" "$TEXT"
  ffmpeg -v error -y -i "$JOB/input/speech.aiff" -ar 16000 -ac 1 "$JOB/input/speech.wav"
  echo "  macOS voice: $VOICE"
else
  echo "  no Japanese 'say' voice — downloading two public test clips"
  B="https://huggingface.co/datasets/japanese-asr"
  curl -fsSL "$B/ja_asr.jsut_basic5000/resolve/main/sample.flac" -o "$JOB/input/a.flac"
  curl -fsSL "$B/ja_asr.reazonspeech_test/resolve/main/sample.flac" -o "$JOB/input/b.flac"
  [ "$(shasum -a 256 "$JOB/input/a.flac" | cut -d' ' -f1)" = 405c0e8fc9dab69497f2068e06f6bc23324af022aed1644472fcc5a2231d32f7 ] || { echo "checksum mismatch"; exit 1; }
  [ "$(shasum -a 256 "$JOB/input/b.flac" | cut -d' ' -f1)" = fa1cf1e86a39eb34e6184eac0fcc7860fac6c9d4dfa283deb3e480faa1ac76fb ] || { echo "checksum mismatch"; exit 1; }
  ffmpeg -v error -y -i "$JOB/input/a.flac" -i "$JOB/input/b.flac" -i "$JOB/input/a.flac" -filter_complex \
    "[0:a]aresample=16000,apad=pad_dur=0.8[a0];[1:a]aresample=16000,apad=pad_dur=0.8[a1];[2:a]aresample=16000[a2];[a0][a1][a2]concat=n=3:v=0:a=1" \
    -ac 1 "$JOB/input/speech.wav"
  TEXT="水をマレーシアから買わなくてはならないのです。大橋さんはやっぱり大変でしたか？水をマレーシアから買わなくてはならないのです。"
fi
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$JOB/input/speech.wav")"
echo "  speech: ${DUR}s"

echo "== synthetic 16:9 'facecam' source (face box right of center)"
ffmpeg -v error -y -f lavfi -i "color=c=0x223344:s=1920x1080:r=30" -i "$JOB/input/speech.wav" -filter_complex \
  "[0:v]drawbox=x=1120:y=340:w=360:h=360:color=0xE0B080:t=fill,drawbox=x=1200:y=470:w=40:h=40:color=black:t=fill,drawbox=x=1360:y=470:w=40:h=40:color=black:t=fill[v]" \
  -map "[v]" -map 1:a -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac "$JOB/input/テスト動画.mp4"

echo "== pipeline"
run "intake (Japanese file name)" bash "$LVS" intake.sh "$JOB/input/テスト動画.mp4" "$JOB"
run "probe + contact sheet" bash "$LVS" probe.sh "$JOB"
T0=$(date +%s)
echo "  transcribing with '$MODEL' (first run downloads the model)…"
run "transcribe ($MODEL)" bash "$LVS" transcribe "$JOB/work/source.mp4" "$JOB/work/transcript.json" --lang ja --model "$MODEL"
echo "  transcription took $(( $(date +%s)-T0 ))s for ${DUR}s of audio"
GOT="$("$LVS_PYTHON" -I -c 'import json,sys;d=json.load(open(sys.argv[1]));print("".join(s["text"] for s in d["segments"]))' "$JOB/work/transcript.json" 2>/dev/null || echo '(no transcript)')"
echo "  expected: $TEXT"; echo "  got     : $GOT"
HALF="$(awk -v d="$DUR" 'BEGIN{printf "%.2f", d/2}')"; END="$(awk -v d="$DUR" 'BEGIN{printf "%.2f", d}')"
run "build facecam clip (word-pop)" bash "$LVS" build_clip.sh "$JOB" --start 0 --end "$HALF" --kind facecam --face-cx 0.66 \
  --caption-mode ass --title "再生数が*10倍*になるコツ" --hook true --out "$JOB/shorts/01_facecam.mp4"
run "build screen clip (karaoke, long title)" bash "$LVS" build_clip.sh "$JOB" --start 0 --end "$END" --kind screen --style karaoke \
  --caption-mode ass --title "誰も教えてくれない*本当の*ショート動画の伸ばし方" --hook true --out "$JOB/shorts/02_screen.mp4"

echo "== outputs"
for f in "$JOB"/shorts/*.mp4; do
  [ -f "$f" ] || continue
  WH="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$f")"
  AU="$(ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 "$f")"
  if [ "$WH" = "1080,1920" ] && [ -n "$AU" ]; then res 0 "$(basename "$f"): ${WH/,/x}, audio=$AU"; else res 1 "$(basename "$f"): ${WH:-?}, audio=${AU:-none}"; fi
  # caption band must stay inside the frame (no text touching the left/right 40px)
  EDGE="$(ffmpeg -v error -i "$f" -vf "fps=5,crop=1080:420:0:1150,format=gray" -f rawvideo - | "$LVS_PYTHON" -I -c '
import sys
d=sys.stdin.buffer.read(); W,H=1080,420; hit=0
for i in range(0,len(d),W):
    r=d[i:i+W]
    if max(r[:40] or b"\0")>230 or max(r[-40:] or b"\0")>230: hit+=1
print(hit)')"
  if [ "$EDGE" = 0 ]; then res 0 "$(basename "$f"): captions inside frame"; else res 1 "$(basename "$f"): text touches frame edge ($EDGE rows)"; fi
  ffmpeg -v error -y -ss 1.0 -i "$f" -frames:v 1 "${f%.mp4}_preview.png"
done

echo
echo "Result: $PASS passed, $FAILS failed"
echo "Job dir: $JOB  (open the *_preview.png and the .mp4 files to check by eye)"
[ "$FAILS" = 0 ]
