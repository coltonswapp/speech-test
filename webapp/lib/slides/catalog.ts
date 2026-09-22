import { CATALOG_KANJI, CATALOG_WORD_SEEDS } from "./catalog-data";
import type {
  CatalogKanji,
  CatalogWord,
  CatalogWordCharacter,
  SlideCatalog,
} from "./types";

const kanjiByCharacter = new Map(
  CATALOG_KANJI.map((entry) => [entry.character, entry])
);

function characterFromKanji(character: string): CatalogWordCharacter | null {
  const row = kanjiByCharacter.get(character);
  if (!row) return null;
  return {
    character: row.character,
    meanings: row.meanings,
    onReadings: row.onReadings,
    kunReadings: row.kunReadings,
  };
}

function buildWords(): CatalogWord[] {
  const words: CatalogWord[] = [];
  for (const seed of CATALOG_WORD_SEEDS) {
    const characters: CatalogWordCharacter[] = [];
    let ok = true;
    for (const character of seed.expression) {
      const detail = characterFromKanji(character);
      if (!detail) {
        ok = false;
        break;
      }
      characters.push(detail);
    }
    if (!ok || characters.length < 2 || characters.length > 3) continue;
    const glossOptions = seed.glossOptions?.length
      ? seed.glossOptions
      : [seed.gloss];
    words.push({
      expression: seed.expression,
      reading: seed.reading,
      gloss: seed.gloss,
      glossOptions,
      characters,
    });
  }
  return words;
}

export const SLIDE_CATALOG: SlideCatalog = {
  kanji: CATALOG_KANJI,
  words: buildWords(),
};

export function findKanji(character: string): CatalogKanji | undefined {
  return kanjiByCharacter.get(character);
}

export function findWord(expression: string): CatalogWord | undefined {
  return SLIDE_CATALOG.words.find((word) => word.expression === expression);
}

export function searchKanji(query: string, limit = 40): CatalogKanji[] {
  const trimmed = query.trim();
  if (!trimmed) return SLIDE_CATALOG.kanji.slice(0, 80);
  if (trimmed.length === 1) {
    const exact = findKanji(trimmed);
    if (exact) return [exact];
  }
  const lower = trimmed.toLowerCase();
  return SLIDE_CATALOG.kanji
    .filter((entry) => {
      if (entry.character === trimmed) return true;
      if (entry.meanings.some((meaning) => meaning.toLowerCase().includes(lower))) {
        return true;
      }
      if (entry.onReadings.some((reading) => reading.includes(trimmed))) return true;
      if (entry.kunReadings.some((reading) => reading.includes(trimmed))) return true;
      return false;
    })
    .slice(0, limit);
}

export function searchWords(query: string, limit = 40): CatalogWord[] {
  const trimmed = query.trim();
  if (!trimmed) return SLIDE_CATALOG.words.slice(0, 60);
  const lower = trimmed.toLowerCase();
  return SLIDE_CATALOG.words
    .filter((word) => {
      if (word.expression.includes(trimmed)) return true;
      if (word.reading.includes(trimmed)) return true;
      if (word.gloss.toLowerCase().includes(lower)) return true;
      if (word.glossOptions.some((gloss) => gloss.toLowerCase().includes(lower))) {
        return true;
      }
      return false;
    })
    .slice(0, limit);
}

export function defaultBadgeMeanings(meanings: string[]): string[] {
  return meanings.slice(0, 2);
}

export function displayBadgeMeaning(
  meanings: string[],
  selected?: string[] | null
): string {
  const picks =
    selected && selected.length > 0
      ? selected.filter((meaning) => meanings.includes(meaning)).slice(0, 2)
      : defaultBadgeMeanings(meanings);
  const shown = picks.length > 0 ? picks : defaultBadgeMeanings(meanings);
  return shown.join(", ") || "—";
}
