import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, eq, inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueScenario, ttsProject, ttsVariant } from "@/lib/db/schema";
import type { DialogueLine } from "@/lib/dialogue/types";
import { conversationContentHash } from "@/lib/tts/content-hash";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";
import { isPublishStale } from "@/lib/dialogue/publish";

// Per-scenario audio readiness for a collection: whether a take is selected
// and whether it's stale relative to the current dialogue lines. Drives the
// badges next to scenarios in the collection editor.

export type ScenarioAudioStatus = {
  id: string;
  hasProject: boolean;
  hasSelectedTake: boolean;
  stale: boolean;
  published: boolean;
  publishStale: boolean;
};

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/audio-status">
) {
  const { collectionId } = await ctx.params;

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
  const selectedVariantIds = projects
    .map((p) => p.selectedVariantId)
    .filter((id): id is string => !!id);
  const variants = selectedVariantIds.length
    ? await db.query.ttsVariant.findMany({
        where: inArray(ttsVariant.id, selectedVariantIds),
      })
    : [];
  const variantById = new Map(variants.map((v) => [v.id, v]));
  const projectByScenarioId = new Map(
    projects.map((p) => [p.sourceScenarioId, p])
  );

  const statuses: ScenarioAudioStatus[] = scenarios.map((scenario) => {
    const project = projectByScenarioId.get(scenario.id);
    const variant = project?.selectedVariantId
      ? variantById.get(project.selectedVariantId)
      : undefined;
    const currentHash = conversationContentHash(
      scenarioLinesToConversation(scenario.lines as DialogueLine[]).lines
    );
    return {
      id: scenario.id,
      hasProject: !!project,
      hasSelectedTake: !!variant,
      stale: !!variant?.contentHash && variant.contentHash !== currentHash,
      published: !!scenario.publishedAudioUrl,
      publishStale: isPublishStale(scenario),
    };
  });

  return NextResponse.json({ scenarios: statuses });
}
