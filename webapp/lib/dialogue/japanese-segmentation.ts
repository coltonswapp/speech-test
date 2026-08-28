// Port of shizen JapaneseSegmentationMapping: map Gemini surfaces onto the
// input as exact substrings, drop punctuation-only tokens, split on internal
// punctuation, require ≥90% coverage, then glue んですけど-style endings.

export type SegmentedToken = {
  text: string;
  start: number;
  end: number;
};

const TOKEN_BOUNDARY_PUNCTUATION = new Set([
  "。",
  "．",
  ".",
  "｡",
  "､",
  "、",
  "，",
  ",",
  "！",
  "!",
  "？",
  "?",
  "…",
  "⋯",
  "‥",
  "・",
  "･",
  "：",
  ":",
  "；",
  ";",
  "「",
  "」",
  "『",
  "』",
  "【",
  "】",
  "（",
  "）",
  "(",
  ")",
  "［",
  "］",
  "[",
  "]",
  "〜",
  "~",
]);

const EXPLANATORY_COPULAS = new Set(["です", "だ"]);
const EXPLANATORY_SOFTENERS = new Set(["けど", "か", "よ", "から", "が"]);

function isWhitespaceChar(char: string): boolean {
  return /^\s$/u.test(char);
}

export function isAllPunctuationOrWhitespace(word: string): boolean {
  if (!word) return false;
  return [...word].every((char) => {
    if (isWhitespaceChar(char)) return true;
    if (TOKEN_BOUNDARY_PUNCTUATION.has(char)) return true;
    return /\p{P}/u.test(char);
  });
}

function isAcceptableSurface(word: string): boolean {
  if (!word) return false;
  return ![...word].some((char) => /[A-Za-z]/.test(char));
}

function significantChars(text: string): string {
  return [...text]
    .filter((char) => !isWhitespaceChar(char) && !isAllPunctuationOrWhitespace(char))
    .join("");
}

function splitTokenOnPunctuation(
  token: SegmentedToken,
  fullText: string
): SegmentedToken[] {
  const surface = token.text;
  const hasBoundary = [...surface].some(
    (char) =>
      TOKEN_BOUNDARY_PUNCTUATION.has(char) ||
      isWhitespaceChar(char) ||
      /\p{P}/u.test(char)
  );
  if (!hasBoundary) return [token];

  const pieces: SegmentedToken[] = [];
  let pieceStart: number | null = null;
  let index = token.start;
  while (index < token.end) {
    const char = fullText[index];
    const next = index + char.length;
    if (isAllPunctuationOrWhitespace(char)) {
      if (pieceStart != null) {
        const text = fullText.slice(pieceStart, index);
        if (text) pieces.push({ text, start: pieceStart, end: index });
        pieceStart = null;
      }
    } else if (pieceStart == null) {
      pieceStart = index;
    }
    index = next;
  }
  if (pieceStart != null) {
    const text = fullText.slice(pieceStart, token.end);
    if (text) pieces.push({ text, start: pieceStart, end: token.end });
  }
  return pieces;
}

function coversInput(tokens: SegmentedToken[], text: string): boolean {
  const significantInput = significantChars(text);
  if (!significantInput) return true;
  const mapped = significantChars(tokens.map((token) => token.text).join(""));
  if (!mapped) return false;
  return mapped.length >= Math.floor(significantInput.length * 0.9);
}

function mergeExplanatorySuffixPair(
  a: SegmentedToken,
  b: SegmentedToken,
  fullText: string
): SegmentedToken | null {
  if (a.end !== b.start) return null;
  const isNGlue = a.text === "ん" && EXPLANATORY_COPULAS.has(b.text);
  const isSoftenerGlue =
    a.text.startsWith("ん") &&
    (a.text.endsWith("です") || a.text.endsWith("だ")) &&
    EXPLANATORY_SOFTENERS.has(b.text);
  if (!isNGlue && !isSoftenerGlue) return null;
  const merged = fullText.slice(a.start, b.end);
  if (!merged) return null;
  return { text: merged, start: a.start, end: b.end };
}

export function mergeColloquialExplanatorySuffixes(
  tokens: SegmentedToken[],
  fullText: string
): SegmentedToken[] {
  if (tokens.length < 2) return tokens;
  let current = tokens;
  let changed = true;
  while (changed) {
    changed = false;
    const out: SegmentedToken[] = [];
    let i = 0;
    while (i < current.length) {
      if (i + 1 < current.length) {
        const merged = mergeExplanatorySuffixPair(
          current[i],
          current[i + 1],
          fullText
        );
        if (merged) {
          out.push(merged);
          i += 2;
          changed = true;
          continue;
        }
      }
      out.push(current[i]);
      i += 1;
    }
    current = out;
  }
  return current;
}

export function validatedTokens(
  surfaces: string[],
  text: string
): SegmentedToken[] | null {
  if (surfaces.length === 0) return null;

  const tokens: SegmentedToken[] = [];
  let searchStart = 0;

  for (const surface of surfaces) {
    const word = surface.trim();
    if (!word) return null;
    if (!isAcceptableSurface(word)) return null;
    const index = text.indexOf(word, searchStart);
    if (index < 0) return null;
    if (!isAllPunctuationOrWhitespace(word)) {
      tokens.push({ text: word, start: index, end: index + word.length });
    }
    searchStart = index + word.length;
  }

  const split = tokens.flatMap((token) => splitTokenOnPunctuation(token, text));
  if (!coversInput(split, text)) return null;
  return mergeColloquialExplanatorySuffixes(split, text);
}
