export const RECOMMENDED_HASHTAGS = [
  "#learnjapanese",
  "#japanese",
  "#studytok",
  "#jlpt",
  "#kanji",
  "#nihongo",
  "#japaneselanguage",
  "#studyjapanese",
  "#日本語",
  "#languagelearning",
];

export const INTRO_TITLE_PRESETS = [
  "Kanji Spotlight",
  "Today's Kanji",
  "Kanji of the Day",
  "One Kanji",
  "Reading Spotlight",
];

export const DEFAULT_INTRO_TITLE = INTRO_TITLE_PRESETS[0];

export const DEFAULT_PART_LABEL_PREFIX = "Kanji is literal, part ";

export function defaultPartLabel(lastExportedPart: number): string {
  return `${DEFAULT_PART_LABEL_PREFIX}${Math.max(0, lastExportedPart) + 1}`;
}

export function parsePartNumber(label: string): number | null {
  const match = /part\s*(\d+)/i.exec(label);
  if (!match) return null;
  const value = Number.parseInt(match[1], 10);
  return Number.isFinite(value) ? value : null;
}

export function formatHashtagLine(tags: string[]): string {
  return tags.join(" ");
}
