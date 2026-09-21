import "server-only";

import { inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsProject, ttsVariant } from "@/lib/db/schema";
import { isPublishKaraokeStale } from "@/lib/dialogue/publish-lockstep";
import {
  buildScenarioReadiness,
  type ScenarioReadiness,
} from "@/lib/dialogue/scenario-readiness";
import { estimatedWavDurationSeconds } from "@/lib/dialogue/token-sync";
import type { DialogueLine } from "@/lib/dialogue/types";
import { currentAmbienceMixHash } from "@/lib/tts/ambience-mix";
import { conversationContentHash } from "@/lib/tts/content-hash";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";
import { isPublishStale } from "@/lib/dialogue/publish";

export type ScenarioReadinessSource = {
  id: string;
  publishedAudioUrl: string | null;
  publishedVariantId: string | null;
  publishedContentHash?: string | null;
  publishedAmbienceHash?: string | null;
  ambienceAssetId?: string | null;
  ambienceGainDb?: number | null;
  ambienceOffsetSeconds?: number | null;
  ambienceLayers?: unknown;
  lines: unknown;
  quiz: unknown;
  tokenSync: unknown;
};

export type ScenarioCurriculumMeta = {
  readiness: ScenarioReadiness;
  /** Trimmed published-take length; null when unpublished or take missing. */
  publishedAudioDurationSeconds: number | null;
};

/**
 * Curriculum readiness + published-take duration for a batch of scenarios,
 * sharing the same TTS project/variant lookups as GET /api/content/dialogues.
 */
export async function loadScenarioCurriculumMetaById(
  scenarios: ScenarioReadinessSource[],
): Promise<Map<string, ScenarioCurriculumMeta>> {
  const result = new Map<string, ScenarioCurriculumMeta>();
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
            sampleRate: true,
            audioByteCount: true,
            trimSampleLower: true,
            trimSampleUpper: true,
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
    const spokenLines = scenarioLinesToConversation(
      scenario.lines as DialogueLine[],
    ).lines;
    const contentHash = conversationContentHash(spokenLines);
    const mixHash = currentAmbienceMixHash({
      assetId: scenario.ambienceAssetId ?? null,
      gainDb: scenario.ambienceGainDb ?? null,
      offsetSeconds: scenario.ambienceOffsetSeconds ?? null,
      layers: scenario.ambienceLayers,
    });
    const audioStale = isPublishStale(
      {
        publishedAudioUrl: scenario.publishedAudioUrl,
        publishedContentHash: scenario.publishedContentHash ?? null,
        publishedAmbienceHash: scenario.publishedAmbienceHash ?? null,
        lines: scenario.lines,
      },
      mixHash,
    );
    const take = selectedVariant ?? publishedVariant;
    const karaokeStale = isPublishKaraokeStale({
      publishedTokenSync: scenario.tokenSync,
      take,
      lines: scenario.lines,
      contentHash,
    });
    const publishedAudioDurationSeconds =
      scenario.publishedAudioUrl && publishedVariant
        ? estimatedWavDurationSeconds(publishedVariant)
        : null;
    result.set(scenario.id, {
      readiness: buildScenarioReadiness({
        publishedAudioUrl: scenario.publishedAudioUrl,
        audioStale,
        karaokeStale,
        lines: scenario.lines,
        quiz: scenario.quiz,
        tokenSync: scenario.tokenSync,
        publishedMarks: publishedVariant?.dialogueLineSwitchSamples,
        workingMarks: selectedVariant?.dialogueLineSwitchSamples,
        workingTokenSync: take?.tokenSync,
        contentHash,
      }),
      publishedAudioDurationSeconds,
    });
  }

  return result;
}

/** Readiness-only view of {@link loadScenarioCurriculumMetaById}. */
export async function loadScenarioReadinessById(
  scenarios: ScenarioReadinessSource[],
): Promise<Map<string, ScenarioReadiness>> {
  const meta = await loadScenarioCurriculumMetaById(scenarios);
  const result = new Map<string, ScenarioReadiness>();
  for (const [id, entry] of meta) {
    result.set(id, entry.readiness);
  }
  return result;
}
