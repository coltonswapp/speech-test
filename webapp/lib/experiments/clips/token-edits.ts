// Hand edits to a clip sentence's tokens (split, merge, reading). Client-safe
// and pure: the editor previews with these, the PATCH route re-validates.
//
// Tokens cover the sentence's words in order; punctuation and spaces between
// them are not tokens. Merges and reading fixes keep their timings
// (carryTimings); split halves have none until "Align edited lines".

export type EditableToken = { text: string; reading?: string };

const KANA_RE = /^[ぁ-ゟァ-ヿー〜]+$/u;
const SKIPPABLE_RE = /[\s\p{P}\p{S}]/u;

export function isKana(text: string): boolean {
  return KANA_RE.test(text);
}

/** Katakana → hiragana so readings compare across scripts (ー stays). */
function toHiragana(text: string): string {
  return text.replace(/[ァ-ヶ]/gu, (ch) => String.fromCharCode(ch.charCodeAt(0) - 0x60));
}

/** Start/end of each token in `text`, in order; null if any is missing or out of order. */
export function tokenRanges(
  text: string,
  tokens: EditableToken[]
): Array<{ start: number; end: number }> | null {
  const ranges: Array<{ start: number; end: number }> = [];
  let from = 0;
  for (const token of tokens) {
    if (!token.text) return null;
    const start = text.indexOf(token.text, from);
    if (start < 0) return null;
    // Only punctuation or spaces may sit between tokens.
    if ([...text.slice(from, start)].some((ch) => !SKIPPABLE_RE.test(ch))) return null;
    ranges.push({ start, end: start + token.text.length });
    from = start + token.text.length;
  }
  if ([...text.slice(from)].some((ch) => !SKIPPABLE_RE.test(ch))) return null;
  return ranges;
}

/** Why `tokens` can't stand for `text`, or null when they can. */
export function clipTokensProblem(text: string, tokens: EditableToken[]): string | null {
  if (tokens.length === 0) return "A sentence needs at least one token.";
  if (!tokenRanges(text, tokens)) {
    return "Tokens must spell out the sentence in order, skipping only punctuation and spaces.";
  }
  return null;
}

/** Grapheme boundaries inside `text` (code-unit offsets, excluding 0 and the end). */
export function splitOffsets(text: string): number[] {
  const offsets: number[] = [];
  let offset = 0;
  const parts =
    typeof Intl !== "undefined" && "Segmenter" in Intl
      ? [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text)].map(
          (p) => p.segment
        )
      : [...text];
  for (let i = 0; i < parts.length - 1; i++) {
    offset += parts[i].length;
    offsets.push(offset);
  }
  return offsets;
}

/**
 * Readings for the two halves of a split. A kana half reads as itself, and the
 * other half gets what's left of the original reading (有名じゃない ゆうめいじゃない
 * → 有名 ゆうめい + じゃない). When that can't be worked out, the non-kana half
 * gets no reading; set it by hand.
 */
function splitReadings(
  left: string,
  right: string,
  reading: string | undefined
): [string | undefined, string | undefined] {
  const leftKana = isKana(left);
  const rightKana = isKana(right);
  const own = (kana: boolean, surface: string) => (kana ? surface : undefined);
  if (!reading) return [own(leftKana, left), own(rightKana, right)];
  const r = toHiragana(reading);
  if (rightKana && r.endsWith(toHiragana(right)) && r.length > right.length) {
    return [reading.slice(0, reading.length - right.length), right];
  }
  if (leftKana && r.startsWith(toHiragana(left)) && r.length > left.length) {
    return [left, reading.slice(left.length)];
  }
  return [own(leftKana, left), own(rightKana, right)];
}

export function splitToken(
  tokens: EditableToken[],
  index: number,
  offset: number
): EditableToken[] | null {
  const token = tokens[index];
  if (!token || !splitOffsets(token.text).includes(offset)) return null;
  const left = token.text.slice(0, offset);
  const right = token.text.slice(offset);
  const [leftReading, rightReading] = splitReadings(left, right, token.reading);
  return [
    ...tokens.slice(0, index),
    { text: left, ...(leftReading ? { reading: leftReading } : {}) },
    { text: right, ...(rightReading ? { reading: rightReading } : {}) },
    ...tokens.slice(index + 1),
  ];
}

/** Merges token `index` with the next one; null if punctuation separates them. */
export function mergeWithNext(
  text: string,
  tokens: EditableToken[],
  index: number
): EditableToken[] | null {
  const a = tokens[index];
  const b = tokens[index + 1];
  const ranges = tokenRanges(text, tokens);
  if (!a || !b || !ranges || ranges[index].end !== ranges[index + 1].start) return null;
  const readingOf = (t: EditableToken) => t.reading ?? (isKana(t.text) ? t.text : undefined);
  const ra = readingOf(a);
  const rb = readingOf(b);
  const reading = ra && rb ? ra + rb : undefined;
  return [
    ...tokens.slice(0, index),
    { text: a.text + b.text, ...(reading ? { reading } : {}) },
    ...tokens.slice(index + 2),
  ];
}

type TimedToken = EditableToken & {
  startSec?: number;
  endSec?: number;
  score?: number;
  readingFallback?: boolean;
};

/**
 * Timings that survive an edit, by where each token sits in `text`:
 * - same span as an old token: keeps its times (and score; the reading-fallback
 *   flag only while the reading is unchanged),
 * - exactly covers several whole old tokens (a merge): first one's start, last
 *   one's end, lowest score,
 * - anything else (a split half): no times; Align edited lines fills them.
 * Returns `next` with times attached where they carry over.
 */
export function carryTimings(
  text: string,
  previous: TimedToken[],
  next: EditableToken[]
): TimedToken[] {
  const oldRanges = tokenRanges(text, previous);
  const newRanges = tokenRanges(text, next);
  if (!oldRanges || !newRanges) return next.map((t) => ({ ...t }));
  return next.map((token, i) => {
    const { start, end } = newRanges[i];
    const first = oldRanges.findIndex((r) => r.start === start);
    const last = oldRanges.findIndex((r) => r.end === end);
    if (first < 0 || last < first) return { ...token };
    const covered = previous.slice(first, last + 1);
    const startSec = covered[0].startSec;
    const endSec = covered[covered.length - 1].endSec;
    if (startSec === undefined || endSec === undefined) return { ...token };
    const scores = covered.map((t) => t.score).filter((s): s is number => s !== undefined);
    const sameToken = covered.length === 1 && covered[0].reading === token.reading;
    return {
      ...token,
      startSec,
      endSec,
      ...(scores.length > 0 ? { score: Math.min(...scores) } : {}),
      ...(sameToken && covered[0].readingFallback !== undefined
        ? { readingFallback: covered[0].readingFallback }
        : {}),
    };
  });
}

export function setReading(
  tokens: EditableToken[],
  index: number,
  reading: string
): EditableToken[] {
  const cleaned = reading.trim();
  return tokens.map((token, i) => {
    if (i !== index) return token;
    return cleaned ? { text: token.text, reading: cleaned } : { text: token.text };
  });
}
