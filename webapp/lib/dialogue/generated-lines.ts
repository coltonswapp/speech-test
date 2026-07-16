import type { DialogueLine, GeneratedLines } from "@/lib/dialogue/types";

export function dialogueLinesFromGenerated(
  generated: GeneratedLines,
  fallbackGrammarPointIds: string[]
): DialogueLine[] {
  return generated.lines.map((line) => ({
    speaker: line.speaker,
    japanese: line.japanese,
    romaji: line.romaji,
    english: line.english,
    grammarPointIDs:
      line.grammarPointIDs && line.grammarPointIDs.length > 0
        ? line.grammarPointIDs
        : fallbackGrammarPointIds.length > 0
          ? fallbackGrammarPointIds
          : undefined,
  }));
}

export function generationBriefFromSetting(
  setting: string,
  menuTitle?: string
): string {
  const trimmed = setting.trim();
  if (!trimmed) return menuTitle?.trim() ?? "";
  if (menuTitle?.trim()) {
    return `${menuTitle.trim()} — ${trimmed}`;
  }
  return trimmed;
}
