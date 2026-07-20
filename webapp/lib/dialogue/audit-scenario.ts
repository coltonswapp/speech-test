import {
  runDeterministicAudit,
  type DeterministicAuditInput,
} from "@/lib/dialogue/audit-deterministic";
import { addMissingGrammarPatterns } from "@/lib/dialogue/enrich-highlights";
import { sanitizeScenarioGrammarTags } from "@/lib/dialogue/sanitize-grammar-tags";
import {
  auditDialogueWithGemini,
  DialogueGenerationError,
} from "@/lib/dialogue/gemini-audit";
import type {
  AuditIssue,
  AuditProposedPatch,
  AuditScenarioResult,
  DialogueHighlights,
  DialogueLine,
  LlmAuditResult,
} from "@/lib/dialogue/types";

export type AuditScenarioParams = {
  lines: DialogueLine[];
  highlights: DialogueHighlights | null;
  grammarPointIds: string[];
  setting?: string;
  menuTitle?: string;
  grammarPointContext: Array<{
    id: string;
    title: string;
    pattern?: string | null;
    shortDefinition?: string | null;
  }>;
  /** Full grammar point catalog; defaults to ids from grammarPointContext. */
  knownGrammarPointIds?: Set<string>;
};

function stripMistaggedIds(
  lines: DialogueLine[],
  mistagged: LlmAuditResult["mistaggedLines"]
): DialogueLine[] {
  if (mistagged.length === 0) return lines;

  const toStrip = new Map<number, Set<string>>();
  for (const entry of mistagged) {
    if (entry.lineIndex < 0 || entry.lineIndex >= lines.length) continue;
    const line = lines[entry.lineIndex];
    if (!(line.grammarPointIDs ?? []).includes(entry.grammarPointID)) continue;
    if (!toStrip.has(entry.lineIndex)) {
      toStrip.set(entry.lineIndex, new Set());
    }
    toStrip.get(entry.lineIndex)!.add(entry.grammarPointID);
  }

  if (toStrip.size === 0) return lines;

  return lines.map((line, index) => {
    const strip = toStrip.get(index);
    if (!strip) return line;
    const grammarPointIDs = (line.grammarPointIDs ?? []).filter(
      (id) => !strip.has(id)
    );
    return {
      ...line,
      grammarPointIDs:
        grammarPointIDs.length > 0 ? grammarPointIDs : undefined,
    };
  });
}

function highlightsEqual(
  a: DialogueHighlights | null,
  b: DialogueHighlights | null
): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

function linesEqual(a: DialogueLine[], b: DialogueLine[]): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

function buildProposedPatch(
  originalLines: DialogueLine[],
  originalHighlights: DialogueHighlights | null,
  originalGrammarPointIds: string[],
  fixedLines: DialogueLine[],
  fixedHighlights: DialogueHighlights | null,
  fixedGrammarPointIds: string[]
): AuditProposedPatch {
  const proposed: AuditProposedPatch = {};
  if (!linesEqual(originalLines, fixedLines)) {
    proposed.lines = fixedLines;
  }
  if (!highlightsEqual(originalHighlights, fixedHighlights)) {
    proposed.highlights = fixedHighlights ?? undefined;
  }
  if (
    JSON.stringify(originalGrammarPointIds) !==
    JSON.stringify(fixedGrammarPointIds)
  ) {
    proposed.grammarPointIds = fixedGrammarPointIds;
  }
  return proposed;
}

function llmIssues(mistagged: LlmAuditResult["mistaggedLines"]): AuditIssue[] {
  return mistagged.map((entry) => ({
    severity: "error" as const,
    code: "mistagged_line_grammar",
    message: `Line ${entry.lineIndex + 1}: "${entry.grammarPointID}" does not match — ${entry.reason}`,
    lineIndex: entry.lineIndex,
    grammarPointID: entry.grammarPointID,
  }));
}

export async function auditScenarioContent(
  params: AuditScenarioParams
): Promise<AuditScenarioResult> {
  const knownGrammarPointIds =
    params.knownGrammarPointIds ??
    new Set(params.grammarPointContext.map((point) => point.id));

  const deterministicInput: DeterministicAuditInput = {
    lines: params.lines,
    highlights: params.highlights,
    grammarPointIds: params.grammarPointIds,
    knownGrammarPointIds,
  };

  const deterministic = runDeterministicAudit(deterministicInput);
  const issues: AuditIssue[] = [...deterministic.issues];

  let mistagged: LlmAuditResult["mistaggedLines"] = [];
  let llmFailed = false;

  try {
    const llmResult = await auditDialogueWithGemini({
      lines: params.lines,
      setting: params.setting,
      menuTitle: params.menuTitle,
      grammarPointContext: params.grammarPointContext,
    });
    mistagged = llmResult.mistaggedLines;
    issues.push(...llmIssues(mistagged));
  } catch (error) {
    llmFailed = true;
    const message =
      error instanceof DialogueGenerationError
        ? error.message
        : "Semantic audit failed.";
    issues.push({
      severity: "warning",
      code: "llm_audit_failed",
      message: `Gemini semantic check skipped: ${message}`,
    });
  }

  let fixedLines = stripMistaggedIds(params.lines, mistagged);

  let fixedHighlights: DialogueHighlights | null = params.highlights;
  if (deterministic.dedupedGrammarPatterns) {
    fixedHighlights = {
      vocabulary: params.highlights?.vocabulary ?? [],
      grammarPatterns: deterministic.dedupedGrammarPatterns,
      contextNotes: params.highlights?.contextNotes ?? [],
    };
  }

  if (deterministic.missingGrammarPatternIds.length > 0) {
    const pointMap = new Map(
      params.grammarPointContext.map((point) => [
        point.id,
        { title: point.title, pattern: point.pattern ?? null },
      ])
    );
    const withMissing = addMissingGrammarPatterns(
      fixedHighlights,
      deterministic.missingGrammarPatternIds,
      pointMap
    );
    if (withMissing) {
      fixedHighlights = withMissing;
    }
  }

  const catalogSanitized = sanitizeScenarioGrammarTags(
    {
      lines: fixedLines,
      highlights: fixedHighlights,
      grammarPointIds: params.grammarPointIds,
    },
    knownGrammarPointIds
  );
  fixedLines = catalogSanitized.lines;
  fixedHighlights = catalogSanitized.highlights;
  const fixedGrammarPointIds = catalogSanitized.grammarPointIds;

  const proposed = buildProposedPatch(
    params.lines,
    params.highlights,
    params.grammarPointIds,
    fixedLines,
    fixedHighlights,
    fixedGrammarPointIds
  );

  return {
    issues,
    proposed,
    ...(llmFailed ? { llmFailed: true } : {}),
  };
}
