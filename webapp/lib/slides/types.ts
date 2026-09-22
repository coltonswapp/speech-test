export const SHOWCASE_KINDS = ["compound", "verb"] as const;
export type ShowcaseKind = (typeof SHOWCASE_KINDS)[number];

export const DECK_KINDS = ["spotlight", "decomposition"] as const;
export type DeckKind = (typeof DECK_KINDS)[number];

export const DECK_STATUSES = ["draft", "approved", "exported"] as const;
export type DeckStatus = (typeof DECK_STATUSES)[number];

export const EXPORT_SIZE_IDS = ["feedPortrait", "square", "story"] as const;
export type ExportSizeId = (typeof EXPORT_SIZE_IDS)[number];

export const RECIPE_IDS = ["studio-light", "studio-dark", "japan-scatter", "japan-wash"] as const;
export type RecipeId = (typeof RECIPE_IDS)[number];

export const BACKGROUND_MODES = ["solid", "wash", "scatter"] as const;
export type BackgroundMode = (typeof BACKGROUND_MODES)[number];

export const ITEM_SOURCES = ["catalog", "write-in"] as const;
export type ItemSource = (typeof ITEM_SOURCES)[number];

export type CatalogShowcaseItem = {
  expression: string;
  reading: string;
  gloss: string;
  kind: ShowcaseKind;
  glossOptions?: string[];
};

export type CatalogKanji = {
  character: string;
  meanings: string[];
  onReadings: string[];
  kunReadings: string[];
  compounds: CatalogShowcaseItem[];
  verbs: CatalogShowcaseItem[];
};

export type CatalogWordCharacter = {
  character: string;
  meanings: string[];
  onReadings: string[];
  kunReadings: string[];
};

export type CatalogWord = {
  expression: string;
  reading: string;
  gloss: string;
  glossOptions: string[];
  characters: CatalogWordCharacter[];
};

export type SlideCatalog = {
  kanji: CatalogKanji[];
  words: CatalogWord[];
};

export type SpotlightItem = {
  id: string;
  expression: string;
  reading: string;
  gloss: string;
  kind: ShowcaseKind;
  source: ItemSource;
};

export type SpotlightPayload = {
  character: string;
  meanings: string[];
  onReadings: string[];
  kunReadings: string[];
  introTitle: string;
  badgeMeanings: string[];
  highlightColor: string;
  items: SpotlightItem[];
  hashtags: string[];
};

export type DecompositionCharacter = {
  character: string;
  meanings: string[];
  onReadings: string[];
  kunReadings: string[];
  badgeMeanings: string[];
};

export type DecompositionPayload = {
  expression: string;
  reading: string;
  gloss: string;
  glossOptions: string[];
  partLabel: string;
  definitionOverride: string | null;
  characters: DecompositionCharacter[];
  hashtags: string[];
};

export type DeckPayload = SpotlightPayload | DecompositionPayload;

export type SlideshowDeck = {
  id: string;
  createdAt: string;
  updatedAt: string;
  kind: DeckKind;
  status: DeckStatus;
  usedSubject: string;
  recipeId: RecipeId;
  exportSize: ExportSizeId;
  photoSet: string;
  photoSeed: number;
  payload: DeckPayload;
};

export type SlideshowPhoto = {
  id: string;
  createdAt: string;
  updatedAt: string;
  title: string;
  tags: string[];
  objectKey: string;
  thumbObjectKey: string;
  contentType: string;
  byteCount: number;
  width: number;
  height: number;
};

export function photoImageUrl(id: string): string {
  return `/api/content/slides/photos/${id}/image`;
}

export function photoThumbUrl(id: string): string {
  return `/api/content/slides/photos/${id}/thumb`;
}

export type SlideRecipe = {
  id: RecipeId;
  name: string;
  background: {
    mode: BackgroundMode;
    scrim: string;
    scatterCount: number;
  };
  colors: {
    page: string;
    surface: string;
    border: string;
    text: string;
    muted: string;
    tertiary: string;
    badgeBg: string;
    badgeText: string;
    watermark: string;
    shadow: string;
  };
  type: {
    titleSize: number;
    titleWeight: number;
    heroSize: number;
    japaneseSize: number;
    bodySize: number;
    captionSize: number;
    watermarkSize: number;
    heroFont: string;
    uiFont: string;
  };
  chrome: {
    watermark: string;
    cornerRadius: number;
    cardBorderWidth: number;
    heroWidth: number;
    subjectHeroWidth: number;
    exampleHeroWidth: number;
    badgePlacement: "center" | "trailingEdgeCentered";
  };
};

export const MAX_COMPOUNDS = 4;
export const MAX_VERBS = 2;
export const MAX_HASHTAGS = 5;
export const MAX_BADGE_MEANINGS = 2;

export function isSpotlightPayload(
  payload: DeckPayload,
  kind: DeckKind
): payload is SpotlightPayload {
  return kind === "spotlight";
}

export function isDecompositionPayload(
  payload: DeckPayload,
  kind: DeckKind
): payload is DecompositionPayload {
  return kind === "decomposition";
}
