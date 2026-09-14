import "server-only";

import { inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsProject, ttsVariant } from "@/lib/db/schema";
import {
  buildScenarioReadiness,
  type ScenarioReadiness,
} from "@/lib/dialogue/scenario-readiness";
import type { DialogueLine } from "@/lib/dialogue/types";
import { conversationContentHash } from "@/lib/tts/content-hash";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";

export type ScenarioReadinessSource = {
  id: string;
  publishedAudioUrl: string | null;
  publishedVariantId: string | null;
  lines: unknown;
  quiz: unknown;
  tokenSync: unknown;
};

/**
 * Compute curriculum-style readiness for a batch of scenarios, sharing the
 * same TTS project/variant lookups as GET /api/content/dialogues.
 */
export async function loadScenarioReadinessById(
  scenarios: ScenarioReadinessSource[],
): Promise<Map<string, ScenarioReadiness>> {
  const result = new Map<string, ScenarioReadiness>();
  if (scenarios.length === 0) return result;

  const scenarioIds = scenarios.map((s) => s.id);
  const projects = await db.query.ttsProject.findMany({
    where: inArray(ttsProject.sourceScenarioId, scenarioIds),
    columns: {
      sourceScenarioId: true,
      selectedVariantId: true,
    },
  });
  const projectByScenarioId = new Map(
    projects.map((p) => [p.sourceScenarioId, p]),
  );

  const variantIds = new Set<string>();
  for (const scenario of scenarios) {
    if (scenario.publishedVariantId) {
      variantIds.add(scenario.publishedVariantId);
    }
    const selected = projectByScenarioId.get(scenario.id)?.selectedVariantId;
    if (selected) variantIds.add(selected);
  }

  const variants =
    variantIds.size > 0
      ? await db.query.ttsVariant.findMany({
          where: inArray(ttsVariant.id, [...variantIds]),
          columns: {
            id: true,
            dialogueLineSwitchSamples: true,
            tokenSync: true,
            contentHash: true,
          },
        })
      : [];
  const variantById = new Map(variants.map((v) => [v.id, v]));

  for (const scenario of scenarios) {
    const publishedVariant = scenario.publishedVariantId
      ? variantById.get(scenario.publishedVariantId)
      : undefined;
    const selectedVariantId = projectByScenarioId.get(
      scenario.id,
    )?.selectedVariantId;
    const selectedVariant = selectedVariantId
      ? variantById.get(selectedVariantId)
      : undefined;
    // Prefer the published take's line marks; fall back to the selected take
    // so drafts still show timing progress.
    const timingVariant = publishedVariant ?? selectedVariant;
    const workingSyncVariant = publishedVariant ?? selectedVariant;
    const spokenLines = scenarioLinesToConversation(
      scenario.lines as DialogueLine[],
    ).lines;
    const contentHash = conversationContentHash(spokenLines);
    result.set(
      scenario.id,
      buildScenarioReadiness({
        publishedAudioUrl: scenario.publishedAudioUrl,
        lines: scenario.lines,
        quiz: scenario.quiz,
        tokenSync: scenario.tokenSync,
        markSamples: timingVariant?.dialogueLineSwitchSamples,
        workingTokenSync: workingSyncVariant?.tokenSync,
        contentHash,
      }),
    );
  }

  return result;
}
