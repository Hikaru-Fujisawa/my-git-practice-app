#!/usr/bin/env bash
# Install joe-jns/long-video-to-shorts as a Claude Code skill on macOS, adapted for Japanese.
#
#   bash install.sh              # check everything, then install
#   bash install.sh --check      # only report what would happen (writes nothing)
#   bash install.sh --brew-ffmpeg  # if no ffmpeg with libass is found, `brew install ffmpeg` (free)
#
# What it does (and does not do):
#   - clones upstream at a pinned commit, applies ./overlay (Japanese + macOS fixes),
#     downloads Noto Sans JP Bold (SIL OFL, sha256-checked) -> ~/.claude/skills/long-video-to-shorts
#   - creates a dedicated venv from free-dev's python-env for faster-whisper (pinned)
#   - never replaces the system Python/Node, never edits shell profiles or PATH,
#     never overwrites an existing skill or venv (stops instead), uses no paid service.
# Compatible with macOS /bin/bash 3.2.
set -euo pipefail

UPSTREAM_URL="https://github.com/joe-jns/long-video-to-shorts.git"
UPSTREAM_COMMIT="61bd65f29b3e2a8b1062d6f0da4042451d796965"
FONT_URL="https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/SubsetOTF/JP/NotoSansJP-Bold.otf"
FONT_SHA256="1b0edfb500b73a4fa8a4fcaae1bbbd403994e08e73e3e0da37e70d3853f42c5f"

FREE_DEV="${FREE_DEV:-/Users/fujisawaakira/Documents/Codex/tools/free-dev}"
BASE_PY="${BASE_PY:-$FREE_DEV/python-env/bin/python}"
VENV="${LVS_VENV:-$FREE_DEV/venvs/long-video-to-shorts}"
MODELS="${LVS_HF_HOME:-$FREE_DEV/cache/huggingface}"
SKILLS_DIR="$HOME/.claude/skills"
DEST="$SKILLS_DIR/long-video-to-shorts"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHECK_ONLY=0; BREW_FFMPEG=0
for a in "$@"; do case "$a" in
  --check) CHECK_ONLY=1;; --brew-ffmpeg) BREW_FFMPEG=1;;
  *) echo "unknown option: $a"; exit 2;; esac; done

ok(){ printf '  [ok]   %s\n' "$*"; }
warn(){ printf '  [warn] %s\n' "$*"; }
fail(){ printf '  [stop] %s\n' "$*"; STOP=1; }
STOP=0

has_libass(){ local f; f="$("$1" -hide_banner -filters 2>/dev/null || true)"; printf '%s\n' "$f" | grep ' subtitles ' >/dev/null; }
node_ok(){ "$1" -e 'const m=+process.versions.node.split(".")[0];process.exit(m>=18&&typeof Intl.Segmenter==="function"&&[...new Intl.Segmenter("ja",{granularity:"word"}).segment("水を買う")].length>1?0:1)' 2>/dev/null; }

# candidate binaries: PATH first, then free-dev, then Homebrew locations
candidates(){ # $1 = binary name
  type -a -p "$1" 2>/dev/null || true
  [ -d "$FREE_DEV" ] && find "$FREE_DEV" -maxdepth 4 -name "$1" -type f -perm -u+x 2>/dev/null | grep -v '/venvs/' || true
  for d in /opt/homebrew/bin /usr/local/bin; do [ -x "$d/$1" ] && echo "$d/$1"; done
  return 0
}

echo "== 1. environment"
[ "$(uname -s)" = "Darwin" ] && ok "macOS $(sw_vers -productVersion 2>/dev/null) ($(uname -m))" || warn "not macOS ($(uname -s)) — continuing anyway"
for t in git curl shasum tar; do command -v "$t" >/dev/null && ok "$t: $(command -v $t)" || fail "$t not found"; done

echo "== 2. existing skill / venv (never overwritten)"
if [ -e "$DEST" ]; then fail "$DEST already exists — remove or rename it yourself, then re-run"; else ok "no skill at $DEST"; fi
OTHERS="$(find "$HOME/.claude" -maxdepth 6 -type d -name 'long-video-to-shorts*' 2>/dev/null | grep -v "^$DEST\$" || true)"
[ -n "$OTHERS" ] && warn "other copies with the same name exist (left untouched):"$'\n'"$OTHERS" || ok "no other same-name skill under ~/.claude"
if [ -e "$VENV" ] && [ ! -f "$VENV/.lvs-owner" ]; then fail "$VENV exists and was not created by this installer"; elif [ -e "$VENV" ]; then ok "reusing own venv $VENV"; else ok "venv will be created at $VENV"; fi

echo "== 3. python (free-dev)"
if [ -x "$BASE_PY" ]; then
  PYV="$("$BASE_PY" -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
  "$BASE_PY" -c 'import sys,venv;sys.exit(0 if sys.version_info>=(3,9) else 1)' && ok "$BASE_PY (Python $PYV)" || fail "$BASE_PY is Python $PYV (need >= 3.9 with venv)"
else fail "$BASE_PY not found"; fi

echo "== 4. ffmpeg with libass"
FFMPEG=""
for c in $(candidates ffmpeg); do
  if has_libass "$c" && [ -x "$(dirname "$c")/ffprobe" ]; then FFMPEG="$c"; break; else warn "$c: no subtitles filter (libass) or no ffprobe next to it"; fi
done
if [ -z "$FFMPEG" ] && [ "$BREW_FFMPEG" = 1 ] && [ "$CHECK_ONLY" = 0 ] && command -v brew >/dev/null; then
  echo "  installing ffmpeg with Homebrew (free; does not touch Python/Node)…"
  brew install ffmpeg
  for c in $(candidates ffmpeg); do has_libass "$c" && [ -x "$(dirname "$c")/ffprobe" ] && { FFMPEG="$c"; break; }; done
fi
[ -n "$FFMPEG" ] && ok "$FFMPEG ($("$FFMPEG" -version | head -1 | cut -d' ' -f3))" \
  || fail "no ffmpeg with libass found. Free options: re-run with --brew-ffmpeg (Homebrew), or put a static ffmpeg+ffprobe build into $FREE_DEV/bin"

echo "== 5. node (>=18 with Intl.Segmenter)"
NODE=""
for c in $(candidates node); do node_ok "$c" && { NODE="$c"; break; } || warn "$c: too old or no full ICU"; done
[ -n "$NODE" ] && ok "$NODE ($("$NODE" -v))" || fail "no usable node found (system Node is not modified by this script)"

echo "== 6. network sources (all free, no account)"
for u in "$FONT_URL" "https://pypi.org/simple/faster-whisper/" "https://huggingface.co/api/models/Systran/faster-whisper-small"; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' -L "$u" || echo 000)"
  [ "$code" = 200 ] && ok "$u" || fail "$u -> HTTP $code"
done

if [ "$STOP" = 1 ]; then echo; echo "Stopped before changing anything. Fix the [stop] items above."; exit 1; fi
if [ "$CHECK_ONLY" = 1 ]; then echo; echo "Check passed. Nothing was written (--check)."; exit 0; fi

echo "== 7. build skill"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lvs-install.XXXXXX")"
git clone --quiet "$UPSTREAM_URL" "$TMP/upstream"
[ "$(git -C "$TMP/upstream" rev-parse "$UPSTREAM_COMMIT^{commit}")" = "$UPSTREAM_COMMIT" ] || { echo "pinned commit not found"; exit 1; }
mkdir -p "$TMP/stage"
git -C "$TMP/upstream" archive "$UPSTREAM_COMMIT" | tar -x -C "$TMP/stage"
cp -R "$HERE/overlay/." "$TMP/stage/"
cp "$HERE/JA-MAC-NOTES.md" "$TMP/stage/"
curl -fsSL "$FONT_URL" -o "$TMP/stage/assets/fonts/NotoSansJP-Bold.otf"
[ "$(shasum -a 256 "$TMP/stage/assets/fonts/NotoSansJP-Bold.otf" | cut -d' ' -f1)" = "$FONT_SHA256" ] || { echo "font checksum mismatch"; exit 1; }
PREFIX="$(dirname "$FFMPEG")"; [ "$(dirname "$NODE")" != "$PREFIX" ] && PREFIX="$PREFIX:$(dirname "$NODE")"
cat > "$TMP/stage/local.env" <<EOF
# written by install.sh — machine-specific tool locations, read by scripts/lvs.sh only
LVS_PYTHON="$VENV/bin/python"
LVS_PATH_PREFIX="$PREFIX"
HF_HOME="$MODELS"
EOF
chmod +x "$TMP/stage/scripts/"*.sh
mkdir -p "$SKILLS_DIR"
[ -e "$DEST" ] && { echo "$DEST appeared meanwhile — not overwriting"; exit 1; }
mv "$TMP/stage" "$DEST"
ok "skill installed: $DEST (upstream $UPSTREAM_COMMIT + overlay)"

echo "== 8. dedicated venv"
if [ ! -e "$VENV" ]; then mkdir -p "$(dirname "$VENV")"; "$BASE_PY" -m venv "$VENV"; echo "long-video-to-shorts" > "$VENV/.lvs-owner"; fi
"$VENV/bin/python" -m pip install --quiet --upgrade pip
"$VENV/bin/python" -m pip install --quiet -r "$HERE/requirements.txt"
mkdir -p "$MODELS"
ok "venv ready: $VENV"

echo "== 9. check"
bash "$DEST/scripts/lvs.sh" check
echo
echo "Installed. Next: bash \"$HERE/selftest.sh\"   (renders two test shorts; downloads the Whisper 'small' model ~480MB on first run)"
