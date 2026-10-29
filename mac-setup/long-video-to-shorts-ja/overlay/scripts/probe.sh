#!/usr/bin/env bash
# Emit specs + a 1fps contact sheet the agent reads to classify facecam vs screen.
set -euo pipefail
PROJ="${1:?usage: probe.sh <project-dir>}"
SRC="$PROJ/work/source.mp4"
[ -f "$SRC" ] || { echo "missing $SRC"; exit 2; }

ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,avg_frame_rate:format=duration \
  -of json "$SRC" > "$PROJ/work/probe.json"

# Contact sheet: 60 frames spread over the WHOLE video (6x10 grid), so long sources are
# classified end-to-end (a fixed 1 fps sheet only covered the first minute).
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC" | tr -d '\r')"
FPS="$(awk -v d="$DUR" 'BEGIN{ if (d+0 <= 60) print 1; else printf "%.6f", 60/d }')"
ffmpeg -y -loglevel error -i "$SRC" -vf "fps=${FPS},scale=240:-1,tile=6x10" -frames:v 1 -update 1 \
  "$PROJ/work/contactsheet.png"
echo "probe.json + contactsheet.png written to $PROJ/work/"
