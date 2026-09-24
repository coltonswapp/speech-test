import "server-only";

import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsProject } from "@/lib/db/schema";
import { clearContentQaIfSelectedTakeChanged } from "@/lib/dialogue/content-qa-store";

/**
 * Set a TTS project’s selected take. On a real id change for a
 * scenario-backed project, clears Content QA timestamps for that scenario.
 *
 * Re-selecting the same take is a no-op (no DB write, no QA clear).
 */
export async function setProjectSelectedTake(params: {
  projectId: string;
  nextSelectedTakeId: string | null;
}): Promise<{
  found: boolean;
  changed: boolean;
  previousSelectedTakeId: string | null;
  scenarioId: string | null;
  contentQaCleared: boolean;
}> {
  const project = await db.query.ttsProject.findFirst({
    where: eq(ttsProject.id, params.projectId),
    columns: {
      id: true,
      selectedVariantId: true,
      sourceScenarioId: true,
    },
  });

  if (!project) {
    return {
      found: false,
      changed: false,
      previousSelectedTakeId: null,
      scenarioId: null,
      contentQaCleared: false,
    };
  }

  const previousSelectedTakeId = project.selectedVariantId ?? null;
  const nextSelectedTakeId = params.nextSelectedTakeId;
  const scenarioId = project.sourceScenarioId ?? null;

  if (previousSelectedTakeId === nextSelectedTakeId) {
    return {
      found: true,
      changed: false,
      previousSelectedTakeId,
      scenarioId,
      contentQaCleared: false,
    };
  }

  await db
    .update(ttsProject)
    .set({ selectedVariantId: nextSelectedTakeId, updatedAt: new Date() })
    .where(eq(ttsProject.id, params.projectId));

  const { cleared } = await clearContentQaIfSelectedTakeChanged({
    scenarioId,
    previousSelectedTakeId,
    nextSelectedTakeId,
  });

  return {
    found: true,
    changed: true,
    previousSelectedTakeId,
    scenarioId,
    contentQaCleared: cleared,
  };
}
