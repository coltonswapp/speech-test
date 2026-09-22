import type { CatalogShowcaseItem } from "./types";
import { MAX_COMPOUNDS, MAX_VERBS } from "./types";

function normalizedReadingKey(reading: string): string {
  return reading.trim().toLowerCase();
}

export function suggestedSelection(
  compounds: CatalogShowcaseItem[],
  verbs: CatalogShowcaseItem[],
  compoundCount = 3,
  verbCount = 0
): CatalogShowcaseItem[] {
  const selected: CatalogShowcaseItem[] = [];
  const seenReadings = new Set<string>();
  const capCompounds = Math.min(compoundCount, MAX_COMPOUNDS);
  const capVerbs = Math.min(verbCount, MAX_VERBS);

  for (const item of compounds) {
    const readingKey = normalizedReadingKey(item.reading);
    if (seenReadings.has(readingKey) && selected.length > 0) continue;
    seenReadings.add(readingKey);
    selected.push(item);
    if (selected.length >= capCompounds) break;
  }

  if (selected.length < capCompounds) {
    for (const item of compounds) {
      if (selected.includes(item)) continue;
      selected.push(item);
      if (selected.length >= capCompounds) break;
    }
  }

  const verbPicks: CatalogShowcaseItem[] = [];
  for (const item of verbs) {
    const readingKey = normalizedReadingKey(item.reading);
    if (seenReadings.has(readingKey) && verbPicks.length > 0) continue;
    seenReadings.add(readingKey);
    verbPicks.push(item);
    if (verbPicks.length >= capVerbs) break;
  }
  selected.push(...verbPicks);
  return selected;
}

export function itemKey(item: Pick<CatalogShowcaseItem, "expression" | "kind" | "reading">): string {
  return `${item.kind}:${item.expression}:${item.reading}`;
}
