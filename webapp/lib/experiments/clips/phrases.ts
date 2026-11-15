import type { ClipToken } from "@/lib/experiments/clips/types";

// Phrase breaks: where to wrap a long sentence onto separate lines so it can
// be read a clause at a time. Display only: the sentence stays the unit for
// its translation, grammar highlights and saving. Client-safe, no model
// calls: computed from the text, the tokens and their timings every time the
// payload is built, so tuning a constant here applies to every clip.
//
// A break goes after a token when the text has 、 there, or the speaker
// pauses there. Breaks are only taken when both sides stay long enough to
// read on their own; a phrase that is still too long is then cut at its best
// remaining clause ending or pause.

/** Sentences up to this many characters stay on one line. */
export const PHRASE_SPLIT_MIN_SENTENCE_CHARS = 24;
/** No phrase shorter than this (characters, punctuation included). */
export const PHRASE_MIN_CHARS = 8;
/** A phrase longer than this gets a second pass at weaker break points. */
export const PHRASE_MAX_CHARS = 28;
/** A gap between words this long (s) counts as a pause. */
export const PHRASE_PAUSE_SEC = 0.25;

const COMMA = /[、，,]/;
/**
 * Token endings that close a clause (te-form, たり, reasons, contrast,
 * conditions). Not から: it is as often "from" (明日から) as "because".
 */
const CLAUSE_END = /(て|って|たり|だり|ため|ので|けど|けれど|けれども|ながら|ば|たら|なら|し)$/;
/** Compound particles that end in て but don't end a clause (お金として使う). */
const NOT_CLAUSE_END = /(として|にとって|について|によって|に対して|にして|をもって|において|に関して|に際して|につれて)$/;
/**
 * A token that leans on what came before: breaking in front of it would
 * strand it (…からと思って, …だって, …かな). No break before these.
 */
const LEANS_BACK = /^(と|とか|って|か|かな|かも|の|ね|よ|な|わ|ぞ|さ|も|は|が|を|に|へ|まで|より|という|といった|みたい|ように|ような|こと|もの|です|だ|でしょう|だろう)$/;

export type ClipPhrase = {
  /** Token range in the sentence: [tokenStart, tokenEnd). */
  tokenStart: number;
  tokenEnd: number;
  /** Character range in the sentence text; trailing punctuation belongs to the phrase. */
  charStart: number;
  charEnd: number;
};

/** Where each token sits in the text (tokens map onto it left to right). */
function tokenSpans(text: string, tokens: Pick<ClipToken, "text">[]): Array<[number, number]> | null {
  const spans: Array<[number, number]> = [];
  let cursor = 0;
  for (const token of tokens) {
    const at = text.indexOf(token.text, cursor);
    if (at < 0) return null;
    spans.push([at, at + token.text.length]);
    cursor = at + token.text.length;
  }
  return spans;
}

type Candidate = { after: number; strength: number };

function insideQuote(text: string, at: number): boolean {
  let depth = 0;
  for (const ch of text.slice(0, at)) {
    if (ch === "「" || ch === "『") depth++;
    else if ((ch === "」" || ch === "』") && depth > 0) depth--;
  }
  return depth > 0;
}

/**
 * The sentence's phrases, in order, covering every token and character. One
 * phrase (the whole sentence) when it is short or has nowhere good to break.
 */
export function splitSentencePhrases(
  text: string,
  tokens: Pick<ClipToken, "text" | "startSec" | "endSec">[]
): ClipPhrase[] {
  const whole: ClipPhrase[] = [{ tokenStart: 0, tokenEnd: tokens.length, charStart: 0, charEnd: text.length }];
  if (text.length <= PHRASE_SPLIT_MIN_SENTENCE_CHARS || tokens.length < 2) return whole;
  const spans = tokenSpans(text, tokens);
  if (!spans) return whole;

  // Break after token i: the phrase ends where token i+1 begins (so 、 stays on the left).
  const charAfter = (i: number) => spans[i + 1]![0];
  const candidates: Candidate[] = [];
  for (let i = 0; i < tokens.length - 1; i++) {
    const between = text.slice(spans[i]![1], spans[i + 1]![0]);
    const end = tokens[i]!.endSec;
    const next = tokens[i + 1]!.startSec;
    const pause = end !== undefined && next !== undefined && next - end >= PHRASE_PAUSE_SEC;
    const comma = COMMA.test(between);
    if (!comma && LEANS_BACK.test(tokens[i + 1]!.text)) continue;
    // Never inside a quote: 「え、日帰りだけど行っちゃう？」 stays whole.
    if (insideQuote(text, spans[i + 1]![0])) continue;
    const word = tokens[i]!.text;
    // A bare って token is the quote marker (…」って言った), not a te-form.
    const clause = CLAUSE_END.test(word) && !NOT_CLAUSE_END.test(word) && word !== "って";
    const strength = (comma ? 2 : 0) + (pause ? 1 : 0) + (clause ? 0.5 : 0);
    if (strength > 0) candidates.push({ after: i, strength });
  }

  // Pass 1: every comma that leaves both sides readable. (A pause alone can
  // fall inside a clause, as in dramatic reading: 軸を回る…自転を.)
  const cuts = new Set<number>();
  let phraseStart = 0;
  for (const c of candidates) {
    if (c.strength < 2) continue;
    const at = charAfter(c.after);
    if (at - phraseStart >= PHRASE_MIN_CHARS && text.length - at >= PHRASE_MIN_CHARS) {
      cuts.add(c.after);
      phraseStart = at;
    }
  }

  // Pass 2: phrases still too long take their strongest inner break point
  // (a clause ending, ideally with a pause) nearest the middle, as long as
  // both halves stay readable. A bare pause isn't enough.
  const sorted = () => [...cuts].sort((a, b) => a - b);
  for (let guard = 0; guard < 8; guard++) {
    const bounds = [-1, ...sorted(), tokens.length - 1];
    let changed = false;
    for (let k = 0; k < bounds.length - 1; k++) {
      const startChar = bounds[k]! < 0 ? 0 : charAfter(bounds[k]!);
      const endChar = bounds[k + 1]! >= tokens.length - 1 ? text.length : charAfter(bounds[k + 1]!);
      if (endChar - startChar <= PHRASE_MAX_CHARS) continue;
      const mid = (startChar + endChar) / 2;
      const inner = candidates
        .filter((c) => c.strength !== 1)
        .filter((c) => c.after > bounds[k]! && c.after < bounds[k + 1]! && !cuts.has(c.after))
        .filter((c) => {
          const at = charAfter(c.after);
          return at - startChar >= PHRASE_MIN_CHARS && endChar - at >= PHRASE_MIN_CHARS;
        })
        .sort((a, b) => b.strength - a.strength || Math.abs(charAfter(a.after) - mid) - Math.abs(charAfter(b.after) - mid));
      if (inner[0]) {
        cuts.add(inner[0].after);
        changed = true;
      }
    }
    if (!changed) break;
  }

  if (cuts.size === 0) return whole;
  const phrases: ClipPhrase[] = [];
  let tokenStart = 0;
  let charStart = 0;
  for (const after of sorted()) {
    const charEnd = charAfter(after);
    phrases.push({ tokenStart, tokenEnd: after + 1, charStart, charEnd });
    tokenStart = after + 1;
    charStart = charEnd;
  }
  phrases.push({ tokenStart, tokenEnd: tokens.length, charStart, charEnd: text.length });
  return phrases;
}
