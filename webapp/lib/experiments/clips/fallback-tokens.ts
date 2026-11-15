// Pieces of the tokenize fallback for clip lines. Pure, client-safe.
//
// When Gemini can't segment a whole line (on long, disfluent speech it tends
// to "fix" the wording, so its tokens stop matching), the line is retried in
// clause-sized chunks, which it gets right far more often. Only a chunk that
// still fails gets the plain dictionary word split (Intl.Segmenter), which
// knows nothing about conjugation: 来まして comes back as 来 + まして. That
// split is patched by mergeInflections.

/** Chunks for the retry stay at or under this many characters where possible. */
export const CLAUSE_CHUNK_MAX_CHARS = 30;

const CLAUSE_END_PUNCT = /[、，,。．！？!?…]/;

/**
 * The line cut after its punctuation into chunks of up to `maxChars`
 * (neighbouring short clauses are joined). Concatenated, the chunks are the
 * line. A single clause longer than `maxChars` stays whole.
 */
export function clauseChunks(text: string, maxChars = CLAUSE_CHUNK_MAX_CHARS): string[] {
  const clauses: string[] = [];
  let start = 0;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]!;
    if (!CLAUSE_END_PUNCT.test(ch)) continue;
    // Keep a run of punctuation (！？, 。」) on the same clause.
    let end = i + 1;
    while (end < text.length && (CLAUSE_END_PUNCT.test(text[end]!) || /[」』）)]/.test(text[end]!))) end++;
    clauses.push(text.slice(start, end));
    start = end;
    i = end - 1;
  }
  if (start < text.length) clauses.push(text.slice(start));

  const chunks: string[] = [];
  for (const clause of clauses) {
    const last = chunks[chunks.length - 1];
    if (last !== undefined && last.length + clause.length <= maxChars) {
      chunks[chunks.length - 1] = last + clause;
    } else {
      chunks.push(clause);
    }
  }
  return chunks.filter((c) => c.trim().length > 0);
}

/**
 * Inflectional endings the word splitter cuts off a verb or adjective. They
 * never stand alone, so they always join the word before.
 */
const INFLECTION = /^(ます|ました|まして|ません|ませんでした|ましょう|ませ|まし|たい|たく|たかった|たかっ|たくて|ない|なかった|なかっ|なくて|なく|られる|られ|れる|させる|させ|せる)$/;
/** Single kana that are particles or sentence endings: these stay separate. */
const STANDALONE_KANA = /^[はがをにでとのもへやかねよなわさぞぜ]$/;
const ENDS_IN_KANJI = /\p{Script=Han}$/u;
const KANA_ONLY = /^[\p{Script=Hiragana}\p{Script=Katakana}ー]+$/u;

type Piece = { text: string; reading?: string };

function join(a: Piece, b: Piece): Piece {
  const text = a.text + b.text;
  // A reading only survives when both halves had one (kana-only pieces).
  return a.reading !== undefined && b.reading !== undefined
    ? { text, reading: a.reading + b.reading }
    : KANA_ONLY.test(text)
      ? { text, reading: text }
      : { text };
}

/**
 * Re-joins conjugation the word splitter tore apart: an inflectional ending
 * (来 + まして → 来まして), a bare small っ (たか + っ → たかっ), and a single
 * okurigana kana after a kanji (どら焼 + き → どら焼き), but never a particle.
 */
export function mergeInflections(tokens: Piece[]): Piece[] {
  const out: Piece[] = [];
  for (const token of tokens) {
    const prev = out[out.length - 1];
    const attach =
      prev !== undefined &&
      (INFLECTION.test(token.text) ||
        token.text === "っ" ||
        (token.text.length === 1 &&
          KANA_ONLY.test(token.text) &&
          !STANDALONE_KANA.test(token.text) &&
          ENDS_IN_KANJI.test(prev.text)));
    if (attach) out[out.length - 1] = join(prev, token);
    else out.push(token);
  }
  return out;
}
