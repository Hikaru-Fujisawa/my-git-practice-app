// Build a centered, timed hook-title ASS with one accent-coloured word.
// usage: node hook_ass.cjs "<title with *accent* word>" [fontFamily] [seconds]
// Accent colour, font, duration, position and safe-zone margins come from config.json.
const { load, assColor } = require('./lib_config.cjs');
const { isCJK, emWidth, NO_LINE_START_RE } = require('./ja_text.cjs');
const CFG = load();

const [, , rawTitle, fontArg, secArg] = process.argv;
const FONT = fontArg || CFG.font_family;
const seconds = Math.min(6, Math.max(2, parseFloat(secArg || CFG.hook_seconds)));
const POSY = CFG.hook_pos_y, SAFE = CFG.safe;

const WHITE = '&H00FFFFFF', BLACK = '&H00000000';
const ACC = assColor(CFG.hook_accent_color);
const esc = t => t.replace(/[{}\\]/g, '');

// extract the *accent* word (first marked); strip markers for wrapping
let accent = null;
const m = rawTitle.match(/\*([^*]+)\*/);
if (m) accent = m[1].trim();
const plain = rawTitle.replace(/\*/g, '');

let SIZE = 88;
let lines = [];
if (!isCJK(plain)) {
  // greedy wrap to <=16 chars/line, max 2 lines
  const words = plain.split(/\s+/).filter(Boolean);
  let cur = '';
  for (const w of words) {
    if (cur && (cur.length + 1 + w.length) > 16) { lines.push(cur); cur = w; }
    else cur = cur ? cur + ' ' + w : w;
  }
  if (cur) lines.push(cur);
  while (lines.length > 2) { lines[1] = lines[1] + ' ' + lines.pop(); }
} else {
  // Japanese: wrap by real width (no spaces needed), keep the accent phrase and Latin
  // words unbroken, respect kinsoku, and shrink the font until it fits in 2 lines.
  const avail = 1080 - SAFE.left - SAFE.right - 30;
  // atoms = words (Intl.Segmenter) with the accent phrase kept whole
  const words = s => (typeof Intl !== 'undefined' && Intl.Segmenter)
    ? [...new Intl.Segmenter('ja', { granularity: 'word' }).segment(s)].map(x => x.segment) : [...s];
  const atoms = [];
  for (const [i, part] of (accent ? plain.split(accent) : [plain]).entries()) {
    if (i) atoms.push(accent);
    atoms.push(...words(part));
  }
  const CONTENT_START_RE = /^[\u3400-\u4dbf\u4e00-\u9fff\u30a0-\u30ffA-Za-z0-9\uff10-\uff5a「『（(]/;
  const PHRASE_END_RE = /[\u3041-\u309f、。，！？!?,.」』）)\s]$/;
  const wrap = size => { const L = []; let cur = [];
    const w = arr => emWidth(arr.join('').trim()) * size;
    for (const a of atoms) {
      if (!cur.length && /^\s+$/.test(a)) continue;
      if (cur.length && w([...cur, a]) > avail && !NO_LINE_START_RE.test(a)) {
        // prefer the last phrase boundary that keeps the line >= 40% full
        let k = cur.length;
        for (let j = cur.length - 1; j > 0 && w(cur.slice(0, j)) >= avail * 0.4; j--)
          if (CONTENT_START_RE.test(cur[j]) && PHRASE_END_RE.test(cur[j - 1])) { k = j; break; }
        L.push(cur.slice(0, k).join('').trim()); cur = cur.slice(k);
      }
      cur.push(a);
    }
    if (cur.join('').trim()) L.push(cur.join('').trim()); return L; };
  // 88px down to 64px in 2 lines; only very long titles fall back to 3 lines at 64-52px
  let maxLines = 2;
  for (SIZE = 88; ; SIZE -= 4) {
    if (SIZE < 64) maxLines = 3;
    lines = wrap(SIZE);
    if (lines.length <= maxLines || SIZE <= 52) break;
  }
  while (lines.length > maxLines) { lines[maxLines - 1] = lines[maxLines - 1] + lines.pop(); }
  // never leave the frame: scale the widest line down if it still overflows
  const widest = Math.max(...lines.map(l => emWidth(l))) * SIZE;
  if (widest > avail) SIZE = Math.floor(SIZE * avail / widest);
}

const colourLine = line => {
  if (!accent) return esc(line);
  // \b only knows ASCII word characters, so Japanese accents use a plain substring match
  const re = new RegExp('\\b' + accent.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b');
  if (!(isCJK(accent) ? line.includes(accent) : re.test(line))) return esc(line);
  return esc(line).replace(esc(accent), `{\\c${ACC}&}${esc(accent)}{\\c${WHITE}&}`);
};
const text = lines.map(colourLine).join('\\N');

const cs = x => { const c = Math.round(x*100); const h = Math.floor(c/360000); const mm = Math.floor(c%360000/6000); const s = Math.floor(c%6000/100); const cc = c%100; return `${h}:${String(mm).padStart(2,'0')}:${String(s).padStart(2,'0')}.${String(cc).padStart(2,'0')}`; };

process.stdout.write(`[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Hook,${FONT},${SIZE},${WHITE},${WHITE},${BLACK},&H80000000,1,0,0,0,100,100,0,0,1,7,5,8,${SAFE.left},${SAFE.right},${POSY},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,${cs(0)},${cs(seconds)},Hook,,0,0,0,,${text}
`);
