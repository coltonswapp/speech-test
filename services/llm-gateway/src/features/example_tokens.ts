import { isObject, trimmedString, withoutVerbLabel, withPhraseReading } from "../validate.js";
import { validatedTokens } from "./token_mapping.js";

const KANA_READING = /^[\u3041-\u3096\u30A1-\u30FAー、。？！?!…・〜～]+$/u;
const HIRAGANA = /[\u3041-\u3096]/u;
const JAPANESE = /[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF]/u;

export type ExampleToken = {
  surface: string;
  lemma: string;
  reading: string;
  start: number;
  end: number;
};

export type CommonUseExample = {
  japanese: string;
  reading: string;
  english: string;
  tokens: ExampleToken[];
};

type RawToken = {
  surface: string;
  lemma: string;
  reading: string;
};

function kanaReading(raw: string): string {
  const reading = raw.replace(/[()（）\s]/g, "");
  return KANA_READING.test(reading) && HIRAGANA.test(reading) ? reading : "";
}

function parseRawTokens(raw: unknown): RawToken[] {
  if (!Array.isArray(raw)) return [];
  const tokens: RawToken[] = [];
  for (const item of raw) {
    if (!isObject(item)) continue;
    const surface = trimmedString(item.surface);
    if (!surface || surface.length > 40) continue;
    const lemma = trimmedString(item.lemma) || surface;
    if (lemma.length > 40) continue;
    tokens.push({
      surface,
      lemma,
      reading: kanaReading(trimmedString(item.reading)),
    });
    if (tokens.length === 24) break;
  }
  return tokens;
}

function attachMetadata(mapped: { text: string; start: number; end: number }[], raw: RawToken[]): ExampleToken[] {
  const unused = [...raw];
  return mapped.map((token) => {
    const index = unused.findIndex((item) => {
      const surface = item.surface.trim();
      return surface === token.text || surface.includes(token.text);
    });
    if (index < 0) {
      return {
        surface: token.text,
        lemma: token.text,
        reading: "",
        start: token.start,
        end: token.end,
      };
    }
    const item = unused.splice(index, 1)[0]!;
    const exact = item.surface.trim() === token.text;
    return {
      surface: token.text,
      lemma: exact ? item.lemma : token.text,
      reading: exact ? item.reading : "",
      start: token.start,
      end: token.end,
    };
  });
}

/** Maps model surfaces onto `japanese` with the app tokenizer contract. Empty when they don't. */
export function mappedExampleTokens(raw: unknown, japanese: string): ExampleToken[] {
  const parsed = parseRawTokens(raw);
  if (parsed.length === 0) return [];
  const mapped = validatedTokens(
    parsed.map((token) => token.surface),
    japanese,
  );
  if (!mapped) return [];
  return attachMetadata(mapped, parsed);
}

function phraseReading(japanese: string, reading: string): string {
  if (!/[\u3400-\u4DBF\u4E00-\u9FFF\u3005]/u.test(japanese)) return "";
  return kanaReading(reading);
}

function parseLegacyExample(raw: string): CommonUseExample | null {
  const display = withPhraseReading(withoutVerbLabel(raw));
  if (!display) return null;
  const split = display.match(/^(.*?)\s*[—–]\s*(.+)$/u) ?? display.match(/^(.*?)\s+-\s+(.+)$/u);
  if (!split) {
    return JAPANESE.test(display)
      ? { japanese: display, reading: "", english: "", tokens: [] }
      : null;
  }
  let japanese = split[1].trim();
  const english = split[2].trim();
  if (!japanese || !english || !JAPANESE.test(japanese)) return null;
  let reading = "";
  const readMatch = japanese.match(/^(.*?)\s*[\(（]([^)）]*)[\)）]\s*$/u);
  if (readMatch) {
    japanese = readMatch[1].trim();
    reading = phraseReading(japanese, readMatch[2]);
  }
  if (!japanese) return null;
  return { japanese, reading, english, tokens: [] };
}

function displayString(example: CommonUseExample): string {
  if (!example.english) return example.japanese;
  const phrase = example.reading ? `${example.japanese} (${example.reading})` : example.japanese;
  return withPhraseReading(`${phrase} — ${example.english}`) || `${example.japanese} — ${example.english}`;
}

export function parseOtherUse(raw: unknown): { display: string; example: CommonUseExample } | null {
  if (typeof raw === "string") {
    const example = parseLegacyExample(raw);
    if (!example) return null;
    return { display: displayString(example), example };
  }
  if (!isObject(raw)) return null;
  const fromFields = (() => {
    const japanese = trimmedString(raw.japanese);
    const english = withoutVerbLabel(trimmedString(raw.english));
    if (!japanese || !english || japanese.length > 80 || !JAPANESE.test(japanese)) return null;
    return {
      japanese,
      reading: phraseReading(japanese, trimmedString(raw.reading)),
      english,
      tokens: mappedExampleTokens(raw.tokens, japanese),
    } satisfies CommonUseExample;
  })();
  if (fromFields) {
    return { display: displayString(fromFields), example: fromFields };
  }
  const fallback = parseLegacyExample(
    [trimmedString(raw.japanese), trimmedString(raw.english)].filter(Boolean).join(" — "),
  );
  return fallback ? { display: displayString(fallback), example: fallback } : null;
}
