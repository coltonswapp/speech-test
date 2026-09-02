import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import {
  dialogueScenario,
  ttsDialogueLine,
  ttsProject,
  ttsVariant,
} from "@/lib/db/schema";
import type { DialogueLine } from "@/lib/dialogue/types";
import { conversationContentHash } from "@/lib/tts/content-hash";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";

// Accept the current take as matching the current script: stamp contentHash
// (and publishedContentHash when this take is the live clip) without TTS.

const bodySchema = z.object({
  contentHash: z.string().min(1).optional(),
});

export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/accept-script">
) {
  const { id, variantId } = await ctx.params;
  const body = bodySchema.parse(await request.json().catch(() => ({})));

  const variant = await db.query.ttsVariant.findFirst({
    where: eq(ttsVariant.id, variantId),
  });
  if (!variant || variant.projectId !== id) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const project = await db.query.ttsProject.findFirst({
    where: eq(ttsProject.id, id),
  });
  if (!project) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  let contentHash: string | null = null;

  if (project.sourceScenarioId) {
    const scenario = await db.query.dialogueScenario.findFirst({
      where: eq(dialogueScenario.id, project.sourceScenarioId),
    });
    if (!scenario) {
      return NextResponse.json({ error: "Scenario not found" }, { status: 404 });
    }
    contentHash = conversationContentHash(
      scenarioLinesToConversation(scenario.lines as DialogueLine[]).lines
    );

    const isLiveTake =
      project.selectedVariantId === variantId ||
      scenario.publishedVariantId === variantId;
    if (scenario.publishedAudioUrl && isLiveTake) {
      await db
        .update(dialogueScenario)
        .set({
          publishedContentHash: contentHash,
          updatedAt: new Date(),
        })
        .where(eq(dialogueScenario.id, scenario.id));
    }
  } else {
    if (body.contentHash) {
      contentHash = body.contentHash;
    } else {
      const lines = await db.query.ttsDialogueLine.findMany({
        where: eq(ttsDialogueLine.projectId, id),
        orderBy: [asc(ttsDialogueLine.orderIndex)],
      });
      contentHash = conversationContentHash(
        lines.map((line) => ({ speaker: line.speaker, text: line.text }))
      );
    }
  }

  const [updated] = await db
    .update(ttsVariant)
    .set({ contentHash })
    .where(eq(ttsVariant.id, variantId))
    .returning();

  return NextResponse.json({ variant: updated });
}
