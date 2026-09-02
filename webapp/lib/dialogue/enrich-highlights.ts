import {
  lineGrammarIds,
  type DialogueHighlights,
  type DialogueLine,
  type ExtractedHighlights,
  type GrammarPatternRef,
} from "@/lib/dialogue/types";

export type GrammarPointLabel = {
  title: string;
  pattern: string | null;
};

export type GrammarPointLabelMap = Map<string, GrammarPointLabel>;

export function uniqueGrammarIdsFromLines(
  lines: DialogueLine[],
  scenarioGrammarPointIds: string[] = []
): string[] {
  const ids: string[] = [];
  const seen = new Set<string>();
  for (const id of scenarioGrammarPointIds) {
    if (!seen.has(id)) {
      seen.add(id);
      ids.push(id);
    }
  }
  for (const line of lines) {
    for (const id of lineGrammarIds(line)) {
      if (!seen.has(id)) {
        seen.add(id);
        ids.push(id);
      }
    }
  }
  return ids;
}

export function patternLabelFromCatalog(
  id: string,
  pointMap: GrammarPointLabelMap
): string {
  const point = pointMap.get(id);
  return point?.pattern?.trim() || point?.title || id;
}

function patternKey(pattern: GrammarPatternRef): string {
  const label = pattern.label.trim();
  const id = pattern.grammarPointID ?? "";
  return `${label}|${id}`;
}

function dedupeGrammarPatterns(
  patterns: GrammarPatternRef[]
): GrammarPatternRef[] {
  const seen = new Set<string>();
  const result: GrammarPatternRef[] = [];
  for (const pattern of patterns) {
    const label = pattern.label.trim();
    if (!label) continue;
    const key = patternKey({ ...pattern, label });
    if (seen.has(key)) continue;
    seen.add(key);
    result.push({ ...pattern, label });
  }
  return result;
}

/** Every tagged grammar id appears once in grammarPatterns (AI label preferred). */
export function ensureGrammarCoverage(
  patterns: GrammarPatternRef[],
  taggedGrammarIds: string[],
  pointMap: GrammarPointLabelMap
): GrammarPatternRef[] {
  const byId = new Map<string, GrammarPatternRef>();
  const unlinked: GrammarPatternRef[] = [];

  for (const pattern of patterns) {
    const label = pattern.label.trim();
    if (!label) continue;
    if (pattern.grammarPointID) {
      if (!byId.has(pattern.grammarPointID)) {
        byId.set(pattern.grammarPointID, pattern);
      }
    } else {
      unlinked.push(pattern);
    }
  }

  const covered: GrammarPatternRef[] = taggedGrammarIds.map((id) => {
    const existing = byId.get(id);
    if (existing?.label.trim()) return existing;
    return {
      label: patternLabelFromCatalog(id, pointMap),
      grammarPointID: id,
    };
  });

  const coveredIdSet = new Set(taggedGrammarIds);
  for (const pattern of patterns) {
    if (pattern.grammarPointID && !coveredIdSet.has(pattern.grammarPointID)) {
      unlinked.push(pattern);
    }
  }

  return dedupeGrammarPatterns([...covered, ...unlinked]);
}

export type MergeHighlightsMode = "refresh" | "fillEmpty";

export function mergeExtractedHighlights(
  existing: DialogueHighlights | null,
  extracted: ExtractedHighlights,
  taggedGrammarIds: string[],
  pointMap: GrammarPointLabelMap,
  mode: MergeHighlightsMode = "refresh"
): DialogueHighlights {
  const currentVocabulary = existing?.vocabulary ?? [];
  const currentGrammarPatterns = existing?.grammarPatterns ?? [];
  const currentContextNotes = existing?.contextNotes ?? [];

  const nextVocabulary =
    mode === "refresh" || currentVocabulary.length === 0
      ? extracted.vocabulary
      : currentVocabulary;

  const nextContextNotes =
    mode === "refresh"
      ? extracted.contextNotes && extracted.contextNotes.length > 0
        ? extracted.contextNotes
        : currentContextNotes
      : extracted.contextNotes && extracted.contextNotes.length > 0
        ? currentContextNotes.length === 0
          ? extracted.contextNotes
          : currentContextNotes
        : currentContextNotes;

  let nextGrammarPatterns = currentGrammarPatterns;
  if (extracted.grammarPatterns && extracted.grammarPatterns.length > 0) {
    const coveredIds = new Set(
      extracted.grammarPatterns
        .map((pattern) => pattern.grammarPointID)
        .filter((id): id is string => !!id)
    );
    const leftover = currentGrammarPatterns.filter(
      (pattern) =>
        !pattern.grammarPointID || !coveredIds.has(pattern.grammarPointID)
    );
    nextGrammarPatterns = [...extracted.grammarPatterns, ...leftover];
  } else if (
    mode === "refresh" &&
    currentGrammarPatterns.length === 0 &&
    taggedGrammarIds.length > 0
  ) {
    nextGrammarPatterns = taggedGrammarIds.map((id) => ({
      label: patternLabelFromCatalog(id, pointMap),
      grammarPointID: id,
    }));
  }

  nextGrammarPatterns = ensureGrammarCoverage(
    nextGrammarPatterns,
    taggedGrammarIds,
    pointMap
  );

  return {
    vocabulary: nextVocabulary,
    grammarPatterns: nextGrammarPatterns,
    contextNotes: nextContextNotes,
  };
}

/** Sync grammar patterns from line/scenario tags only (no LLM). */
export function syncGrammarPatternsFromLines(
  highlights: DialogueHighlights | null,
  taggedGrammarIds: string[],
  pointMap: GrammarPointLabelMap
): DialogueHighlights {
  const vocabulary = highlights?.vocabulary ?? [];
  const contextNotes = highlights?.contextNotes ?? [];
  const existingPatterns = highlights?.grammarPatterns ?? [];

  const existingById = new Map<string, GrammarPatternRef>();
  for (const pattern of existingPatterns) {
    if (pattern.grammarPointID) {
      existingById.set(pattern.grammarPointID, pattern);
    }
  }

  const nextPatterns: GrammarPatternRef[] = taggedGrammarIds.map((id) => {
    const existing = existingById.get(id);
    if (existing?.label.trim()) return existing;
    return {
      label: patternLabelFromCatalog(id, pointMap),
      grammarPointID: id,
    };
  });

  for (const pattern of existingPatterns) {
    if (
      !pattern.grammarPointID ||
      !taggedGrammarIds.includes(pattern.grammarPointID)
    ) {
      nextPatterns.push(pattern);
    }
  }

  return {
    vocabulary,
    grammarPatterns: dedupeGrammarPatterns(nextPatterns),
    contextNotes,
  };
}

/** Add missing grammar patterns for line-tagged ids (audit auto-fix). */
export function addMissingGrammarPatterns(
  highlights: DialogueHighlights | null,
  missingIds: string[],
  pointMap: GrammarPointLabelMap
): DialogueHighlights | null {
  if (missingIds.length === 0) return null;

  const vocabulary = highlights?.vocabulary ?? [];
  const contextNotes = highlights?.contextNotes ?? [];
  const grammarPatterns = [...(highlights?.grammarPatterns ?? [])];

  const linkedIds = new Set(
    grammarPatterns
      .map((pattern) => pattern.grammarPointID)
      .filter((id): id is string => !!id)
  );

  let changed = false;
  for (const id of missingIds) {
    if (linkedIds.has(id)) continue;
    grammarPatterns.push({
      label: patternLabelFromCatalog(id, pointMap),
      grammarPointID: id,
    });
    linkedIds.add(id);
    changed = true;
  }

  if (!changed) return null;

  return {
    vocabulary,
    grammarPatterns: dedupeGrammarPatterns(grammarPatterns),
    contextNotes,
  };
}
