#!/usr/bin/env bash
# Run a pipeline step with this machine's tool locations (from <skill>/local.env), without
# touching the system PATH, Python or Node.
#
# usage:
#   lvs.sh check                                   -> show which ffmpeg/node/python are used
#   lvs.sh transcribe <in> <out.json> [--lang ja] [--model small]
#   lvs.sh <script>.sh|.cjs [args...]              -> e.g. lvs.sh build_clip.sh <project> ...
#
# local.env (written by the installer) may set:
#   LVS_PYTHON       python of the dedicated venv that has faster-whisper
#   LVS_PATH_PREFIX  extra dirs (":"-separated) searched first for ffmpeg/ffprobe/node
#   HF_HOME          where Whisper models are cached
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
[ -f "$ROOT/local.env" ] && . "$ROOT/local.env"
[ -n "${LVS_PATH_PREFIX:-}" ] && export PATH="$LVS_PATH_PREFIX:$PATH"
[ -n "${HF_HOME:-}" ] && export HF_HOME
export HF_HUB_DISABLE_SYMLINKS_WARNING=1 HF_HUB_DISABLE_TELEMETRY=1
PY="${LVS_PYTHON:-python3}"

CMD="${1:?usage: lvs.sh check | transcribe <in> <out.json> [...] | <script> [args...]}"; shift
case "$CMD" in
  check)
    echo "ffmpeg : $(command -v ffmpeg || echo MISSING) $(ffmpeg -version 2>/dev/null | head -1 | cut -d' ' -f3)"
    FILTERS="$(ffmpeg -hide_banner -filters 2>/dev/null || true)"
    if printf '%s\n' "$FILTERS" | grep ' subtitles ' >/dev/null; then echo "libass : ok (subtitles filter)"; else echo "libass : MISSING (ffmpeg has no subtitles filter)"; fi
    echo "ffprobe: $(command -v ffprobe || echo MISSING)"
    echo "node   : $(command -v node || echo MISSING) $(node -v 2>/dev/null)"
    echo "segment: $(node -e "process.stdout.write(typeof Intl.Segmenter==='function'?'ok (Intl.Segmenter)':'MISSING')" 2>/dev/null)"
    echo "python : $PY ($("$PY" -V 2>&1))"
    echo "whisper: $("$PY" -I -c 'import faster_whisper,av;print("faster-whisper",faster_whisper.__version__,"/ av",av.__version__)' 2>&1 | tail -1)"
    echo "font   : $(node "$HERE/lib_config.cjs" font_family) -> $(node "$HERE/lib_config.cjs" font_abs)"
    echo "models : ${HF_HOME:-~/.cache/huggingface}"
    ;;
  transcribe) exec "$PY" -I "$HERE/transcribe.py" "$@" ;;
  *.sh)  exec bash "$HERE/$CMD" "$@" ;;
  *.cjs) exec node "$HERE/$CMD" "$@" ;;
  *) echo "unknown command: $CMD"; exit 2 ;;
esac
