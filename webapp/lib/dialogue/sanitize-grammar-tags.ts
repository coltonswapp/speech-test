import type {
  DialogueHighlights,
  DialogueLine,
  ExtractedHighlights,
  GeneratedLine,
  GeneratedLines,
} from "@/lib/dialogue/types";
import {
  filterGrammarPointIds,
  filterGrammarPointIdsRequired,
} from "@/lib/dialogue/grammar-catalog";

export type SanitizeGrammarRemoved = {
  scenarioGrammarPointIds: string[];
  lineTags: Array<{ lineIndex: number; ids: string[] }>;
  highlightPatternIds: string[];
};

export type SanitizedScenarioGrammar = {
  lines: DialogueLine[];
  highlights: DialogueHighlights | null;
  grammarPointIds: string[];
  removed: SanitizeGrammarRemoved;
};

export function sanitizeGeneratedLine(
  line: GeneratedLine,
  approved: Set<string>
): GeneratedLine {
  if (approved.size === 0) {
    const { grammarPointIDs: _unused, ...rest } = line;
    return rest;
  }
  return {
    ...line,
    grammarPointIDs: filterGrammarPointIds(line.grammarPointIDs, approved),
  };
}

export function sanitizeGeneratedLines(
  generated: GeneratedLines,
  approved: Set<string>
): GeneratedLines {
  return {
    ...generated,
    lines: generated.lines.map((line) => sanitizeGeneratedLine(line, approved)),
  };
}

export function sanitizeExtractedHighlights(
  extracted: ExtractedHighlights,
  approved: Set<string>
): ExtractedHighlights {
  if (approved.size === 0) {
    return {
      ...extracted,
      grammarPatterns: extracted.grammarPatterns?.map(
        ({ grammarPointID: _unused, ...pattern }) => pattern
      ),
    };
  }

  return {
    ...extracted,
    grammarPatterns: extracted.grammarPatterns?.map((pattern) => ({
      ...pattern,
      grammarPointID:
        pattern.grammarPointID && approved.has(pattern.grammarPointID)
          ? pattern.grammarPointID
          : undefined,
    })),
  };
}

export function sanitizeScenarioGrammarTags(
  input: {
    lines: DialogueLine[];
    highlights: DialogueHighlights | null;
    grammarPointIds: string[];
  },
  approved: Set<string>
): SanitizedScenarioGrammar {
  const removed: SanitizeGrammarRemoved = {
    scenarioGrammarPointIds: [],
    lineTags: [],
    highlightPatternIds: [],
  };

  for (const id of input.grammarPointIds) {
    if (!approved.has(id)) {
      removed.scenarioGrammarPointIds.push(id);
    }
  }

  const lines = input.lines.map((line, lineIndex) => {
    const before = line.grammarPointIDs ?? [];
    const stripped = before.filter((id) => !approved.has(id));
    if (stripped.length > 0) {
      removed.lineTags.push({ lineIndex, ids: stripped });
    }
    return {
      ...line,
      grammarPointIDs: filterGrammarPointIds(line.grammarPointIDs, approved),
    };
  });

  const grammarPointIds = filterGrammarPointIdsRequired(
    input.grammarPointIds,
    approved
  );

  let highlights = input.highlights;
  if (highlights) {
    const patterns = highlights.grammarPatterns ?? [];
    for (const pattern of patterns) {
      if (pattern.grammarPointID && !approved.has(pattern.grammarPointID)) {
        removed.highlightPatternIds.push(pattern.grammarPointID);
      }
    }
    highlights = {
      vocabulary: highlights.vocabulary ?? [],
      contextNotes: highlights.contextNotes ?? [],
      grammarPatterns: patterns.map((pattern) => ({
        ...pattern,
        grammarPointID:
          pattern.grammarPointID && approved.has(pattern.grammarPointID)
            ? pattern.grammarPointID
            : undefined,
      })),
    };
  }

  return { lines, highlights, grammarPointIds, removed };
}

export function countRemovedGrammarTags(removed: SanitizeGrammarRemoved): number {
  return (
    removed.scenarioGrammarPointIds.length +
    removed.lineTags.reduce((sum, entry) => sum + entry.ids.length, 0) +
    removed.highlightPatternIds.length
  );
}
