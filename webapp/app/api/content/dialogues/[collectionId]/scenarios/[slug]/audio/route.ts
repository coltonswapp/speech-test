import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import {
  dialogueCollection,
  dialogueScenario,
  ttsDialogueGroup,
  ttsProject,
} from "@/lib/db/schema";
import type { DialogueLine } from "@/lib/dialogue/types";
import { conversationContentHash } from "@/lib/tts/content-hash";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";
import { slugifyDialogueGroup } from "@/lib/tts/import-dialogue-scripts";
import { GEMINI_TTS_DEFAULT_MODEL } from "@/lib/tts/gemini-voices";

// The scenario's audio container: the tts_project attached via
// sourceScenarioId. GET reports it (plus the current content hash for
// staleness); POST ensures it exists and updates voices. Lines are never
// copied — generation reads dialogue_scenario.lines directly.

const ensureAudioSchema = z.object({
  speaker1Voice: z.string().min(1).optional(),
  speaker2Voice: z.string().min(1).optional(),
});

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]/audio">
) {
  const { collectionId, slug } = await ctx.params;
  const scenarioId = `${collectionId}/${slug}`;

  const scenario = await db.query.dialogueScenario.findFirst({
    where: eq(dialogueScenario.id, scenarioId),
  });
  if (!scenario) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const conversation = scenarioLinesToConversation(
    scenario.lines as DialogueLine[]
  );
  const project = await db.query.ttsProject.findFirst({
    where: eq(ttsProject.sourceScenarioId, scenarioId),
  });

  return NextResponse.json({
    project: project ?? null,
    currentContentHash: conversationContentHash(conversation.lines),
    speakerNames: conversation.speakerNames,
  });
}

export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]/audio">
) {
  const { collectionId, slug } = await ctx.params;
  const scenarioId = `${collectionId}/${slug}`;

  const body = await request.json().catch(() => ({}));
  const parsed = ensureAudioSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const scenario = await db.query.dialogueScenario.findFirst({
    where: eq(dialogueScenario.id, scenarioId),
  });
  if (!scenario) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  const collection = await db.query.dialogueCollection.findFirst({
    where: eq(dialogueCollection.id, collectionId),
  });
  if (!collection) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const conversation = scenarioLinesToConversation(
    scenario.lines as DialogueLine[]
  );

  // Keep scenario-backed tracks grouped by collection in the TTS sidebar.
  const groupId = slugifyDialogueGroup(collectionId);
  await db
    .insert(ttsDialogueGroup)
    .values({ id: groupId, title: collection.title })
    .onConflictDoUpdate({
      target: ttsDialogueGroup.id,
      set: { title: collection.title },
    });

  const existing = await db.query.ttsProject.findFirst({
    where: eq(ttsProject.sourceScenarioId, scenarioId),
  });

  let project;
  if (existing) {
    [project] = await db
      .update(ttsProject)
      .set({
        speaker1Voice: parsed.data.speaker1Voice ?? existing.speaker1Voice,
        speaker2Voice: parsed.data.speaker2Voice ?? existing.speaker2Voice,
        speaker1Name: conversation.speaker1Name,
        speaker2Name: conversation.speaker2Name,
        trackName: scenario.menuTitle,
        groupId,
        groupOrderIndex: scenario.orderIndex,
        updatedAt: new Date(),
      })
      .where(eq(ttsProject.id, existing.id))
      .returning();
  } else {
    const speaker1Voice = parsed.data.speaker1Voice ?? "Zephyr";
    const speaker2Voice = parsed.data.speaker2Voice ?? "Puck";
    [project] = await db
      .insert(ttsProject)
      .values({
        compositionMode: "conversation",
        provider: "gemini",
        voice: `${speaker1Voice}/${speaker2Voice}`,
        model: GEMINI_TTS_DEFAULT_MODEL,
        speaker1Voice,
        speaker2Voice,
        speaker1Name: conversation.speaker1Name,
        speaker2Name: conversation.speaker2Name,
        trackName: scenario.menuTitle,
        groupId,
        sourceScenarioId: scenarioId,
        groupOrderIndex: scenario.orderIndex,
      })
      .returning();
  }

  return NextResponse.json({
    project,
    currentContentHash: conversationContentHash(conversation.lines),
    speakerNames: conversation.speakerNames,
  });
}
