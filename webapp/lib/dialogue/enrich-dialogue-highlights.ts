"use client";

import { dialogueApi } from "@/lib/dialogue/client";
import {
  mergeExtractedHighlights,
  type GrammarPointLabelMap,
  type MergeHighlightsMode,
  uniqueGrammarIdsFromLines,
} from "@/lib/dialogue/enrich-highlights";
import type { DialogueHighlights, DialogueLine } from "@/lib/dialogue/types";

export async function enrichDialogueHighlights(params: {
  lines: DialogueLine[];
  existing: DialogueHighlights | null;
  grammarPointIds: string[];
  setting?: string;
  menuTitle?: string;
  pointMap: GrammarPointLabelMap;
  mode?: MergeHighlightsMode;
}): Promise<DialogueHighlights> {
  const taggedGrammarIds = uniqueGrammarIdsFromLines(
    params.lines,
    params.grammarPointIds
  );

  const { extracted } = await dialogueApi.extractHighlights({
    lines: params.lines,
    setting: params.setting,
    menuTitle: params.menuTitle,
    grammarPointIds: taggedGrammarIds,
  });

  return mergeExtractedHighlights(
    params.existing,
    extracted,
    taggedGrammarIds,
    params.pointMap,
    params.mode ?? "refresh"
  );
}
