import { defaultBadgeMeanings, findKanji, findWord } from "./catalog";
import { DEFAULT_INTRO_TITLE, defaultPartLabel } from "./hashtags";
import { DEFAULT_HIGHLIGHT_COLOR } from "./highlights";
import { suggestedSelection } from "./selection";
import type {
  DecompositionPayload,
  SpotlightItem,
  SpotlightPayload,
} from "./types";

function itemId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return `item-${Math.random().toString(36).slice(2, 10)}`;
}

export function makeSpotlightPayload(character: string): SpotlightPayload | null {
  const kanji = findKanji(character);
  if (!kanji) return null;
  const picked = suggestedSelection(kanji.compounds, kanji.verbs, 3, 0);
  const items: SpotlightItem[] = picked.map((row) => ({
    id: itemId(),
    expression: row.expression,
    reading: row.reading,
    gloss: row.gloss,
    kind: row.kind,
    source: "catalog",
  }));
  return {
    character: kanji.character,
    meanings: kanji.meanings,
    onReadings: kanji.onReadings,
    kunReadings: kanji.kunReadings,
    introTitle: DEFAULT_INTRO_TITLE,
    badgeMeanings: defaultBadgeMeanings(kanji.meanings),
    highlightColor: DEFAULT_HIGHLIGHT_COLOR,
    items,
    hashtags: ["#learnjapanese", "#kanji", "#nihongo"],
  };
}

export function makeDecompositionPayload(
  expression: string,
  lastExportedPart = 0
): DecompositionPayload | null {
  const word = findWord(expression);
  if (!word) return null;
  return {
    expression: word.expression,
    reading: word.reading,
    gloss: word.gloss,
    glossOptions: word.glossOptions,
    partLabel: defaultPartLabel(lastExportedPart),
    definitionOverride: null,
    characters: word.characters.map((character) => ({
      ...character,
      badgeMeanings: defaultBadgeMeanings(character.meanings),
    })),
    hashtags: ["#learnjapanese", "#kanji", "#nihongo"],
  };
}

export function writeInSpotlightItem(params: {
  expression: string;
  gloss: string;
  reading?: string;
}): SpotlightItem {
  return {
    id: itemId(),
    expression: params.expression.trim(),
    reading: (params.reading ?? "").trim(),
    gloss: params.gloss.trim(),
    kind: "compound",
    source: "write-in",
  };
}
