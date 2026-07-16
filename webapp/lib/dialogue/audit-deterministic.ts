import type {
  AuditIssue,
  DialogueHighlights,
  DialogueLine,
  GrammarPatternRef,
} from "@/lib/dialogue/types";

export type DeterministicAuditInput = {
  lines: DialogueLine[];
  highlights: DialogueHighlights | null;
  grammarPointIds: string[];
  knownGrammarPointIds: Set<string>;
};

export type DeterministicAuditResult = {
  issues: AuditIssue[];
  /** Indices of duplicate grammarPatterns to drop (keep first of each key). */
  duplicatePatternIndices: number[];
  dedupedGrammarPatterns: GrammarPatternRef[] | null;
  /** Line-tagged grammar ids missing from highlights grammarPatterns. */
  missingGrammarPatternIds: string[];
};

function patternKey(pattern: GrammarPatternRef): string {
  const label = pattern.label.trim();
  const id = pattern.grammarPointID ?? "";
  return `${label}|${id}`;
}

function uniqueIdsFromLines(lines: DialogueLine[]): Set<string> {
  const ids = new Set<string>();
  for (const line of lines) {
    for (const id of line.grammarPointIDs ?? []) {
      ids.add(id);
    }
  }
  return ids;
}

export function runDeterministicAudit(
  input: DeterministicAuditInput
): DeterministicAuditResult {
  const issues: AuditIssue[] = [];
  const highlights = input.highlights;
  const grammarPatterns = highlights?.grammarPatterns ?? [];
  const duplicatePatternIndices: number[] = [];
  const seenPatternKeys = new Set<string>();

  for (let index = 0; index < grammarPatterns.length; index++) {
    const pattern = grammarPatterns[index];
    const label = pattern.label.trim();

    if (!label) {
      issues.push({
        severity: "warning",
        code: "empty_pattern_label",
        message: `Grammar pattern #${index + 1} has an empty label.`,
      });
      continue;
    }

    const key = patternKey(pattern);
    if (seenPatternKeys.has(key)) {
      duplicatePatternIndices.push(index);
      issues.push({
        severity: "warning",
        code: "duplicate_grammar_pattern",
        message: `Duplicate grammar pattern "${label}"${pattern.grammarPointID ? ` (${pattern.grammarPointID})` : ""}.`,
        grammarPointID: pattern.grammarPointID,
      });
    } else {
      seenPatternKeys.add(key);
    }

    if (
      pattern.grammarPointID &&
      !input.knownGrammarPointIds.has(pattern.grammarPointID)
    ) {
      issues.push({
        severity: "warning",
        code: "unknown_highlight_grammar_id",
        message: `Highlight pattern "${label}" links to unknown grammar point "${pattern.grammarPointID}".`,
        grammarPointID: pattern.grammarPointID,
      });
    }
  }

  const dedupedGrammarPatterns =
    duplicatePatternIndices.length > 0
      ? grammarPatterns.filter((_, i) => !duplicatePatternIndices.includes(i))
      : null;

  const lineTaggedIds = uniqueIdsFromLines(input.lines);

  for (const id of input.grammarPointIds) {
    if (!lineTaggedIds.has(id)) {
      issues.push({
        severity: "info",
        code: "scenario_id_not_on_lines",
        message: `Scenario grammar point "${id}" is not tagged on any line.`,
        grammarPointID: id,
      });
    }
  }

  for (const id of lineTaggedIds) {
    if (!input.knownGrammarPointIds.has(id)) {
      issues.push({
        severity: "warning",
        code: "unknown_line_grammar_id",
        message: `Line tag "${id}" is not in the grammar catalog.`,
        grammarPointID: id,
      });
    } else if (
      input.grammarPointIds.length > 0 &&
      !input.grammarPointIds.includes(id)
    ) {
      issues.push({
        severity: "info",
        code: "line_id_not_in_scenario",
        message: `Line tag "${id}" is not listed in scenario grammar points.`,
        grammarPointID: id,
      });
    }
  }

  const highlightLinkedIds = new Set(
    grammarPatterns
      .map((p) => p.grammarPointID)
      .filter((id): id is string => !!id)
  );

  const missingGrammarPatternIds: string[] = [];

  for (const id of lineTaggedIds) {
    if (!highlightLinkedIds.has(id)) {
      missingGrammarPatternIds.push(id);
      issues.push({
        severity: "info",
        code: "tagged_id_missing_from_highlights",
        message: `Grammar point "${id}" is tagged on lines but not linked in highlights.`,
        grammarPointID: id,
      });
    }
  }

  return {
    issues,
    duplicatePatternIndices,
    dedupedGrammarPatterns,
    missingGrammarPatternIds,
  };
}
