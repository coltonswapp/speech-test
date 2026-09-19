import { asc, eq, inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import {
  dialogueCollection,
  dialogueScenario,
  ttsProject,
  ttsVariant,
} from "@/lib/db/schema";
import type { CollectionFile, DialogueLine } from "@/lib/dialogue/types";
import { recordPublish } from "@/lib/dialogue/review-timing";
import { karaokeSnapshotForTake } from "@/lib/dialogue/publish-lockstep";
import { conversationContentHash } from "@/lib/tts/content-hash";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";
import { renderVariantM4a } from "@/lib/tts/variant-audio";
import {
  isPublishedR2Configured,
  publishedObjectPublicUrl,
  putPublishedObject,
} from "@/lib/storage/published-r2";
import { getPublicDialogueCollectionFile } from "@/lib/dialogue/public-api";
import { currentAmbienceMixHash } from "@/lib/tts/ambience-mix";
import { publishPrimaryAmbienceBed } from "@/lib/tts/published-ambience";
import {
  isPublishStale,
  publishedAudioUrlLooksMixed,
  publishedDialogueAudioKey,
} from "@/lib/dialogue/publish-audio";

export {
  isPublishStale,
  publishedAudioUrlLooksMixed,
  publishedDialogueAudioKey,
} from "@/lib/dialogue/publish-audio";

export function scenarioSlugFromId(scenarioId: string, collectionId: string): string {
  const prefix = `${collectionId}/`;
  if (!scenarioId.startsWith(prefix)) {
    throw new Error(`Scenario id ${scenarioId} does not belong to ${collectionId}`);
  }
  return scenarioId.slice(prefix.length);
}

export type PublishScenarioResult = {
  scenario: typeof dialogueScenario.$inferSelect;
  publishedAudioUrl: string;
  objectKey: string;
  hasTokenKaraoke: boolean;
};

export async function publishScenarioAudio(
  collectionId: string,
  slug: string
): Promise<PublishScenarioResult> {
  if (!isPublishedR2Configured()) {
    throw new Error(
      "Published R2 is not configured. Set R2_PUBLISHED_BUCKET_NAME and R2_PUBLISHED_PUBLIC_BASE_URL."
    );
  }

  const scenarioId = `${collectionId}/${slug}`;
  const scenario = await db.query.dialogueScenario.findFirst({
    where: eq(dialogueScenario.id, scenarioId),
  });
  if (!scenario) {
    throw new Error("Scenario not found");
  }

  const project = await db.query.ttsProject.findFirst({
    where: eq(ttsProject.sourceScenarioId, scenarioId),
  });
  if (!project?.selectedVariantId) {
    throw new Error("Select a take before publishing.");
  }

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, project.selectedVariantId),
  });
  if (!variant) {
    throw new Error("Selected take no longer exists. Choose another take.");
  }

  const currentHash = conversationContentHash(
    scenarioLinesToConversation(scenario.lines as DialogueLine[]).lines
  );
  const contentHash = variant.contentHash ?? currentHash;
  const scenarioSlug = scenarioSlugFromId(scenarioId, collectionId);
  const objectKey = publishedDialogueAudioKey(
    collectionId,
    scenarioSlug,
    contentHash,
    variant.id
  );
  const publishedAudioUrl = publishedObjectPublicUrl(objectKey);
  const canReuseDryDialogue =
    scenario.publishedAudioUrl === publishedAudioUrl &&
    scenario.publishedVariantId === variant.id &&
    scenario.publishedContentHash === contentHash &&
    !publishedAudioUrlLooksMixed(scenario.publishedAudioUrl);
  if (!canReuseDryDialogue) {
    const m4a = await renderVariantM4a(variant);
    await putPublishedObject(objectKey, m4a, "audio/mp4");
  }
  const mixHash = currentAmbienceMixHash({
    assetId: scenario.ambienceAssetId,
    gainDb: scenario.ambienceGainDb,
    offsetSeconds: scenario.ambienceOffsetSeconds,
    layers: scenario.ambienceLayers,
  });
  await publishPrimaryAmbienceBed(scenario);
  const tokenSync = karaokeSnapshotForTake({
    take: variant,
    lines: scenario.lines,
    contentHash,
  });

  const [updated] = await db
    .update(dialogueScenario)
    .set({
      publishedAudioUrl,
      publishedVariantId: variant.id,
      publishedContentHash: contentHash,
      publishedAmbienceHash: mixHash,
      publishedAt: new Date(),
      audioKey: scenarioId,
      tokenSync,
      updatedAt: new Date(),
    })
    .where(eq(dialogueScenario.id, scenarioId))
    .returning();

  // KA-8 telemetry: open-to-publish time and reviewer corrections by source.
  await recordPublish(variant).catch((error: unknown) => {
    console.error(`[publish] timing record failed for ${variant.id}:`, error);
  });

  return {
    scenario: updated,
    publishedAudioUrl,
    objectKey,
    hasTokenKaraoke: tokenSync != null,
  };
}

export async function unpublishScenarioAudio(
  collectionId: string,
  slug: string
): Promise<typeof dialogueScenario.$inferSelect> {
  const scenarioId = `${collectionId}/${slug}`;
  const [updated] = await db
    .update(dialogueScenario)
    .set({
      publishedAudioUrl: null,
      publishedVariantId: null,
      publishedContentHash: null,
      publishedAmbienceHash: null,
      publishedAt: null,
      tokenSync: null,
      updatedAt: new Date(),
    })
    .where(eq(dialogueScenario.id, scenarioId))
    .returning();
  if (!updated) {
    throw new Error("Scenario not found");
  }
  return updated;
}

export type LessonPublishScenarioResult = {
  id: string;
  menuTitle: string;
  status: "published" | "unchanged" | "skipped" | "failed";
  publishedAudioUrl: string | null;
  hasTokenKaraoke?: boolean;
  error?: string;
};

export type PublishLessonResult = {
  collectionId: string;
  results: LessonPublishScenarioResult[];
  lesson: CollectionFile;
  publishedCount: number;
  skippedCount: number;
  failedCount: number;
};

/**
 * Publishes a whole lesson (dialogue collection): encodes each scenario's
 * selected take to the public CDN when needed, then returns the full lesson
 * JSON Shizen will fetch (all scenarios, with accurate publishedAudioUrl).
 */
export async function publishLesson(
  collectionId: string
): Promise<PublishLessonResult> {
  if (!isPublishedR2Configured()) {
    throw new Error(
      "Published R2 is not configured. Set R2_PUBLISHED_BUCKET_NAME and R2_PUBLISHED_PUBLIC_BASE_URL."
    );
  }

  const collection = await db.query.dialogueCollection.findFirst({
    where: eq(dialogueCollection.id, collectionId),
  });
  if (!collection) {
    throw new Error("Lesson not found");
  }

  const scenarios = await db.query.dialogueScenario.findMany({
    where: eq(dialogueScenario.collectionId, collectionId),
    orderBy: [asc(dialogueScenario.orderIndex)],
  });

  const projects = scenarios.length
    ? await db.query.ttsProject.findMany({
        where: inArray(
          ttsProject.sourceScenarioId,
          scenarios.map((s) => s.id)
        ),
      })
    : [];
  const projectByScenarioId = new Map(
    projects.map((p) => [p.sourceScenarioId, p])
  );
  const selectedVariantIds = projects
    .map((p) => p.selectedVariantId)
    .filter((id): id is string => !!id);
  const variants = selectedVariantIds.length
    ? await db.query.ttsVariant.findMany({
        where: inArray(ttsVariant.id, selectedVariantIds),
      })
    : [];
  const variantById = new Map(variants.map((v) => [v.id, v]));

  const results: LessonPublishScenarioResult[] = [];

  for (const scenario of scenarios) {
    const slug = scenarioSlugFromId(scenario.id, collectionId);
    const project = projectByScenarioId.get(scenario.id);
    const variant = project?.selectedVariantId
      ? variantById.get(project.selectedVariantId)
      : undefined;

    if (!variant) {
      results.push({
        id: scenario.id,
        menuTitle: scenario.menuTitle,
        status: "skipped",
        publishedAudioUrl: scenario.publishedAudioUrl,
        error: "No selected take — scenario JSON ships without CDN audio.",
      });
      continue;
    }

    const currentHash = conversationContentHash(
      scenarioLinesToConversation(scenario.lines as DialogueLine[]).lines
    );
    const contentHash = variant.contentHash ?? currentHash;
    const mixHash = currentAmbienceMixHash({
      assetId: scenario.ambienceAssetId,
      gainDb: scenario.ambienceGainDb,
      offsetSeconds: scenario.ambienceOffsetSeconds,
      layers: scenario.ambienceLayers,
    });
    const alreadyCurrent =
      scenario.publishedAudioUrl &&
      scenario.publishedVariantId === variant.id &&
      scenario.publishedContentHash === contentHash &&
      !isPublishStale(scenario, mixHash);

    if (alreadyCurrent) {
      const tokenSync = karaokeSnapshotForTake({
        take: variant,
        lines: scenario.lines,
        contentHash,
      });
      if (JSON.stringify(scenario.tokenSync ?? null) !== JSON.stringify(tokenSync)) {
        await db
          .update(dialogueScenario)
          .set({ tokenSync, updatedAt: new Date() })
          .where(eq(dialogueScenario.id, scenario.id));
      }
      results.push({
        id: scenario.id,
        menuTitle: scenario.menuTitle,
        status: "unchanged",
        publishedAudioUrl: scenario.publishedAudioUrl,
        hasTokenKaraoke: tokenSync != null,
      });
      continue;
    }

    try {
      const published = await publishScenarioAudio(collectionId, slug);
      results.push({
        id: scenario.id,
        menuTitle: scenario.menuTitle,
        status: "published",
        publishedAudioUrl: published.publishedAudioUrl,
        hasTokenKaraoke: published.hasTokenKaraoke,
      });
    } catch (error) {
      results.push({
        id: scenario.id,
        menuTitle: scenario.menuTitle,
        status: "failed",
        publishedAudioUrl: scenario.publishedAudioUrl,
        error: error instanceof Error ? error.message : "Publish failed",
      });
    }
  }

  const lesson = await getPublicDialogueCollectionFile(collectionId);
  if (!lesson) {
    throw new Error("Failed to assemble lesson JSON after publish.");
  }

  return {
    collectionId,
    results,
    lesson,
    publishedCount: results.filter((r) => r.status === "published").length,
    skippedCount: results.filter((r) => r.status === "skipped").length,
    failedCount: results.filter((r) => r.status === "failed").length,
  };
}
