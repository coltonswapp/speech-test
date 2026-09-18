/**
 * Kana readings for learner tokens (KA-5). Pure helpers shared by the Gemini
 * tokenizer and its tests; the aligner uses the reading instead of guessing
 * pronunciation from the surface (digits, kanji numerals, katakana names).
 */

const KANA_RE = /^[ぁ-ゟァ-ヿー〜]+$/u;
const STRIP_RE = /[\s\p{P}]/gu;

/** Normalize a model-supplied reading; undefined when it is not usable kana. */
export function normalizeReading(raw: unknown): string | undefined {
  if (typeof raw !== "string") return undefined;
  const cleaned = raw.normalize("NFKC").replace(STRIP_RE, "");
  if (!cleaned || !KANA_RE.test(cleaned)) return undefined;
  return cleaned;
}

export type RawToken = { text: string; reading?: string };
export type Span = { text: string; start: number; end: number };

/** Sequential spans of raw surfaces inside `text`, mirroring validatedTokens. */
export function rawTokenSpans(raw: RawToken[], text: string): Array<Span & { reading?: string }> {
  const spans: Array<Span & { reading?: string }> = [];
  let searchStart = 0;
  for (const token of raw) {
    const word = token.text.trim();
    if (!word) continue;
    const index = text.indexOf(word, searchStart);
    if (index < 0) return spans;
    spans.push({ text: word, start: index, end: index + word.length, reading: normalizeReading(token.reading) });
    searchStart = index + word.length;
  }
  return spans;
}

/**
 * Carry readings onto the final segments. A segment that equals one raw span
 * takes its reading; one that exactly covers consecutive raw spans (suffix
 * merge) takes their concatenation; anything else (a punctuation split) gets
 * no reading and the aligner falls back.
 */
export function readingsForSegments(
  segments: Span[],
  rawSpans: Array<Span & { reading?: string }>
): Array<string | undefined> {
  return segments.map((segment) => {
    const covered = rawSpans.filter(
      (span) => span.start >= segment.start && span.end <= segment.end
    );
    if (covered.length === 0) return undefined;
    if (covered[0].start !== segment.start) return undefined;
    if (covered[covered.length - 1].end !== segment.end) return undefined;
    for (let i = 1; i < covered.length; i++) {
      if (covered[i].start !== covered[i - 1].end) return undefined;
    }
    if (covered.some((span) => !span.reading)) return undefined;
    return covered.map((span) => span.reading).join("");
  });
}
