// Japanese / CJK text helpers shared by ass_from_words.cjs and hook_ass.cjs.
// - CJK text is joined WITHOUT spaces (Latin words keep their spaces).
// - Widths are measured in "em" (1.0 = one full-width glyph at the style's font size),
//   so lines can be packed to the real frame width instead of a character count.
// - Whisper emits Japanese as sub-word pieces ("マ","レ","ー"...). resegment() rebuilds
//   natural words with Node's built-in Intl.Segmenter (ICU, no extra dependency) and
//   interpolates per-character timing from the original pieces.
const CJK_RE = /[　-ヿ㐀-䶿一-鿿豈-﫿＀-￯]/;
const SENT_END_RE = /[。！？!?]$/;
const COMMA_RE = /[、，,]$/;
// characters that must not start a line (kinsoku)
const NO_LINE_START_RE = /^[、。，．！？!?,.)）」』】〕…ー〜ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ]/;

const isCJK = s => CJK_RE.test(s);
const hasCJK = ws => ws.some(w => isCJK(w.t));

// Approximate advance widths for a bold sans (Noto Sans JP Bold / DejaVu Sans Bold).
function charEm(ch) {
  if (CJK_RE.test(ch)) return 1.0;
  if (ch === ' ') return 0.3;
  if (/[A-Z0-9MW@%&]/.test(ch)) return 0.7;
  return 0.6;
}
const emWidth = s => [...s].reduce((n, ch) => n + charEm(ch), 0);

const needSpace = (a, b) => !!a && !!b && !isCJK(a.slice(-1)) && !isCJK(b[0]);
// join raw texts; `rendered` (optional) are the same items with ASS tags applied
function joinTexts(raw, rendered) {
  const out = rendered || raw;
  let s = '';
  raw.forEach((t, i) => { if (i && needSpace(raw[i - 1], t)) s += ' '; s += out[i]; });
  return s;
}

// words: [{t,a,b}] -> natural Japanese words with timing. Non-CJK input is returned as-is.
function resegment(ws, gapSplit = 0.3) {
  if (!hasCJK(ws) || typeof Intl === 'undefined' || !Intl.Segmenter) return ws;
  const seg = new Intl.Segmenter('ja', { granularity: 'word' });
  // split into runs at pauses so a word never spans a silence
  const runs = []; let cur = [];
  for (const w of ws) {
    if (cur.length && w.a - cur[cur.length - 1].b > gapSplit) { runs.push(cur); cur = []; }
    cur.push(w);
  }
  if (cur.length) runs.push(cur);

  const out = [];
  for (const run of runs) {
    // per UTF-16 code unit -> {a,b} (characters inside one whisper piece share its span linearly)
    const units = []; let text = '';
    run.forEach((w, i) => {
      if (i && needSpace(run[i - 1].t, w.t)) { text += ' '; units.push({ a: w.a, b: w.a }); }
      const chars = [...w.t]; const n = chars.length; const d = (w.b - w.a) / n;
      chars.forEach((ch, k) => {
        const span = { a: w.a + d * k, b: w.a + d * (k + 1) };
        text += ch; for (let u = 0; u < ch.length; u++) units.push(span);
      });
    });
    let first = true;
    for (const s of seg.segment(text)) {
      const t = s.segment.trim();
      if (!t) continue;
      const lead = s.segment.length - s.segment.trimStart().length;
      const a = units[s.index + lead].a;
      const b = units[s.index + s.segment.trimEnd().length - 1].b;
      const prev = out[out.length - 1];
      // punctuation / symbols attach to the previous word of the same run
      if (!s.isWordLike && !first && prev) { prev.t += t; prev.b = Math.max(prev.b, b); continue; }
      out.push({ t, a, b });
      first = false;
    }
  }
  return out;
}

module.exports = { CJK_RE, SENT_END_RE, COMMA_RE, NO_LINE_START_RE,
  isCJK, hasCJK, charEm, emWidth, needSpace, joinTexts, resegment };
