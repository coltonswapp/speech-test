// Post-ASR line split. Pure, client-safe.
//
// Gemini often returns one huge run-on as a single "sentence". The prompt asks
// for short spoken units; this is the deterministic backstop applied to that
// output before tokenize / align / translate / the clip token index. Existing
// clips are left alone until they are re-transcribed.
//
// Punctuation classes match fallback-tokens.ts; particle / te-form / quote
// handling follows phrases.ts, at character offsets (no tokens yet).

/** Prompt sent with clip audio. */
export const ASR_PROMPT = `Transcribe the Japanese speech in this audio verbatim.

Rules:
- Write exactly what is spoken, in standard Japanese orthography (kanji and kana as a native subtitle would use). Do not summarize, correct grammar, or translate.
- Keep fillers and hesitations that are clearly spoken (えー, あの, まあ). Drop coughs, laughter, music and sound effects.
- Write numbers the way a Japanese subtitle would (e.g. 三つ, 2020年).
- Write English words and phrases the speaker says in katakana, as a Japanese subtitle would (Let's go → レッツゴー！, OK → オッケー). Never use the Latin alphabet.
- Split the transcript into short, natural spoken units, one per array item. Break at natural clause boundaries: after 、, after conjunctive particles (けど, が, から, ので, し), after て-form joins, after quoted speech, and after fillers. Aim for roughly 25–30 Japanese characters per item. Never cut inside a word or a tight phrase. Never drop or paraphrase any spoken text. Keep ending punctuation (。？！、) where natural. Each item should still make sense on its own as much as possible. Keep the order they are spoken in.
- No speaker labels, timestamps, romaji or notes.
- If there is no Japanese speech, return an empty array.`;

/** Re-split any ASR line longer than this. ~one spoken clause. */
export const ASR_LINE_MAX_CHARS = 32;

const CLAUSE_END_PUNCT = /[、，,。．！？!?…]/;
const PUNCT_TRAIL = /[」』）)]/;
const NOT_CLAUSE_END = [
  "として",
  "にとって",
  "について",
  "によって",
  "に対して",
  "にして",
  "をもって",
  "において",
  "に関して",
  "に際して",
  "につれて",
];
/** After a て-form these continue the same predicate (ている, てしまう, …). */
const TE_CONTINUE =
  /^(いる|いて|る|いく|いっ|きた|きて|くる|しまう|しまっ|ちゃう|ちゃっ|ちゃい|おく|おい|ある|あっ|みる|み[たて]|ほしい|ください|いい)/;
/** Longest-first conjunctive endings. Bare で is the case particle, not te-form. */
const PARTICLES = [
  "けれども",
  "けれど",
  "けど",
  "ので",
  "から",
  "まして",
  "くて",
  "して",
  "んで",
  "って",
  "て",
  "が",
  "し",
] as const;

function insideQuote(text: string, at: number): boolean {
  let depth = 0;
  for (const ch of text.slice(0, at)) {
    if (ch === "「" || ch === "『") depth++;
    else if ((ch === "」" || ch === "』") && depth > 0) depth--;
  }
  return depth > 0;
}

function endsWithNotClause(left: string): boolean {
  return NOT_CLAUSE_END.some((p) => left.endsWith(p));
}

function tightTeContinue(left: string, right: string): boolean {
  if (!/(て|んで|して|まして|くて)$/.test(left)) return false;
  return TE_CONTINUE.test(right);
}

/** First index of the right-hand piece after a punctuation (or closing-quote) cut. */
function punctCuts(text: string): number[] {
  const cuts: number[] = [];
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]!;
    if (!CLAUSE_END_PUNCT.test(ch) && ch !== "」" && ch !== "』") continue;
    let end = i + 1;
    while (end < text.length && (CLAUSE_END_PUNCT.test(text[end]!) || PUNCT_TRAIL.test(text[end]!))) {
      end++;
    }
    if (end > 0 && end < text.length && !insideQuote(text, end)) cuts.push(end);
    i = end - 1;
  }
  return cuts;
}

function particleOk(particle: (typeof PARTICLES)[number], text: string, start: number): boolean {
  const before = text.slice(0, start);
  const after = text.slice(start + particle.length);
  if (particle === "が") {
    return /(だ|です|ます|た|ない)$/.test(before);
  }
  if (particle === "し") {
    if (/^(て|ます|た|ない|よう|ろ|か|たい)/.test(after)) return false;
    return /(だ|です|ます|た|い|ん)$/.test(before);
  }
  if (particle === "から") {
    if (/(これ|それ|あれ|どこ|ここ)$/.test(before)) return false;
    if (/^(は|に|の|して|には|こそ|いう)/.test(after)) return false;
  }
  if (particle === "って") {
    if (/^(な|いう|こと|感じ)/.test(after)) return false;
  }
  // Bare て in たちつてと is the mora, not a te-form. Te-form is followed by
  // a new clause, not a particle that leans on the verb (ては, ても, てから).
  if (particle === "て" || particle === "んで") {
    if (/^(と|も|は|が|を|に|へ|の|で|か|ね|よ|な|わ|から|まで|より)/.test(after)) return false;
  }
  return true;
}

/** First index of the right-hand piece after a conjunctive / te-form cut. */
function particleCuts(text: string): number[] {
  const cuts: number[] = [];
  for (let i = 0; i < text.length; i++) {
    for (const particle of PARTICLES) {
      if (!text.startsWith(particle, i)) continue;
      const end = i + particle.length;
      if (end <= 0 || end >= text.length) continue;
      if (insideQuote(text, end)) continue;
      const left = text.slice(0, end);
      if (endsWithNotClause(left)) continue;
      if (tightTeContinue(left, text.slice(end))) continue;
      if (!particleOk(particle, text, i)) continue;
      cuts.push(end);
      break;
    }
  }
  return cuts;
}

function closestToMiddle(text: string, cuts: number[]): number | null {
  if (cuts.length === 0) return null;
  const mid = text.length / 2;
  let best = cuts[0]!;
  let bestDist = Math.abs(best - mid);
  for (const cut of cuts) {
    const dist = Math.abs(cut - mid);
    if (dist < bestDist) {
      best = cut;
      bestDist = dist;
    }
  }
  return best;
}

function bestCut(text: string): number | null {
  return closestToMiddle(text, punctCuts(text)) ?? closestToMiddle(text, particleCuts(text));
}

function splitOne(text: string, maxChars: number): string[] {
  if (text.length <= maxChars) return [text];
  const cut = bestCut(text);
  if (cut == null || cut <= 0 || cut >= text.length) return [text];
  return [...splitOne(text.slice(0, cut), maxChars), ...splitOne(text.slice(cut), maxChars)];
}

/**
 * Re-split oversized ASR lines at the clause boundary closest to the middle
 * (punctuation first, then conjunctive particles). Concatenated, the result
 * is the input: nothing is dropped, added, or reordered. A line with no safe
 * boundary stays whole even if it is over `maxChars`.
 */
export function splitLongAsrLines(lines: string[], maxChars = ASR_LINE_MAX_CHARS): string[] {
  return lines.flatMap((line) => splitOne(line, maxChars));
}
