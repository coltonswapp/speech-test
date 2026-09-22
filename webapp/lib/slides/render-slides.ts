import type {
  DeckKind,
  DeckPayload,
  DecompositionPayload,
  SpotlightPayload,
} from "./types";

export type RenderSlide =
  | { id: string; key: "spotlight-kanji" }
  | { id: string; key: "spotlight-entry"; itemIndex: number }
  | { id: string; key: "decomp-intro" }
  | { id: string; key: "decomp-character"; charIndex: number }
  | { id: string; key: "decomp-teaser" }
  | { id: string; key: "decomp-reveal" };

export function slidesForDeck(
  kind: DeckKind,
  payload: DeckPayload
): RenderSlide[] {
  if (kind === "spotlight") {
    const spotlight = payload as SpotlightPayload;
    return [
      { id: "kanji", key: "spotlight-kanji" },
      ...spotlight.items.map((item, itemIndex) => ({
        id: item.id,
        key: "spotlight-entry" as const,
        itemIndex,
      })),
    ];
  }
  const word = payload as DecompositionPayload;
  return [
    { id: "intro", key: "decomp-intro" },
    ...word.characters.map((character, charIndex) => ({
      id: `char-${character.character}-${charIndex}`,
      key: "decomp-character" as const,
      charIndex,
    })),
    { id: "teaser", key: "decomp-teaser" },
    { id: "reveal", key: "decomp-reveal" },
  ];
}

export function slideFileName(
  index: number,
  slide: RenderSlide,
  payload: DeckPayload
): string {
  const n = String(index + 1).padStart(2, "0");
  if (slide.key === "spotlight-kanji") {
    return `${n}-${(payload as SpotlightPayload).character}.png`;
  }
  if (slide.key === "spotlight-entry") {
    const item = (payload as SpotlightPayload).items[slide.itemIndex];
    return `${n}-${item?.expression ?? "example"}.png`;
  }
  if (slide.key === "decomp-intro") return `${n}-intro.png`;
  if (slide.key === "decomp-character") {
    const character = (payload as DecompositionPayload).characters[slide.charIndex];
    return `${n}-${character?.character ?? "kanji"}.png`;
  }
  if (slide.key === "decomp-teaser") return `${n}-teaser.png`;
  return `${n}-reveal.png`;
}
