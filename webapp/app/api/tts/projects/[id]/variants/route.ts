import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, desc, eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import {
  dialogueScenario,
  ttsDialogueLine,
  ttsProject,
  ttsVariant,
  ttsVariantSentence,
} from "@/lib/db/schema";
import { synthesizeOpenAI, OPENAI_SAMPLE_RATE } from "@/lib/tts/openai";
import {
  synthesizeGeminiConversation,
  GEMINI_TTS_SAMPLE_RATE,
  GEMINI_TTS_DEFAULT_MODEL,
} from "@/lib/tts/gemini-tts";
import { pcm16ToFloat32, pcm16ToWav } from "@/lib/tts/wav";
import { align } from "@/lib/tts/alignment";
import { putObject } from "@/lib/storage/r2";
import { conversationContentHash } from "@/lib/tts/content-hash";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";
import type { ConversationLine } from "@/lib/tts/scenario-conversation";
import type { DialogueLine as ScenarioDialogueLine } from "@/lib/dialogue/types";

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants">
) {
  const { id } = await ctx.params;
  const variants = await db.query.ttsVariant.findMany({
    where: eq(ttsVariant.projectId, id),
    orderBy: [desc(ttsVariant.createdAt)],
  });
  return NextResponse.json({ variants });
}

async function generateNarration(
  project: typeof ttsProject.$inferSelect,
  overrides?: { voice?: string; provider?: string }
) {
  const trimmedText = project.promptText.trim();
  if (!trimmedText) {
    throw new UserFacingError("Track composition is empty.");
  }
  const provider = overrides?.provider ?? project.provider;
  const voice = overrides?.voice ?? project.voice;
  if (provider !== "openai") {
    throw new UserFacingError(
      `Provider "${provider}" is not yet supported for narration.`
    );
  }

  const pcm = await synthesizeOpenAI({
    text: trimmedText,
    voice,
    model: project.model,
    instructions: project.instructions,
  });

  return {
    pcm,
    sampleRate: OPENAI_SAMPLE_RATE,
    voice,
    provider,
    alignmentLines: [trimmedText],
    contentHash: conversationContentHash([
      { speaker: "speaker1", text: trimmedText },
    ]),
  };
}

// Scenario-backed projects speak the scenario's current lines; ad-hoc tracks
// keep their own tts_dialogue_line rows.
async function loadConversationLines(
  project: typeof ttsProject.$inferSelect
): Promise<ConversationLine[]> {
  if (project.sourceScenarioId) {
    const scenario = await db.query.dialogueScenario.findFirst({
      where: eq(dialogueScenario.id, project.sourceScenarioId),
    });
    if (!scenario) {
      throw new UserFacingError("Source scenario no longer exists.");
    }
    const conversation = scenarioLinesToConversation(
      scenario.lines as ScenarioDialogueLine[]
    );
    if (conversation.lines.length === 0) {
      throw new UserFacingError(
        "The scenario has no dialogue lines with a speaker and Japanese text."
      );
    }
    // Keep the project's display fields in sync with the scenario so the TTS
    // sidebar reflects what was actually spoken.
    await db
      .update(ttsProject)
      .set({
        speaker1Name: conversation.speaker1Name,
        speaker2Name: conversation.speaker2Name,
        promptText: conversation.lines
          .map((line) => {
            const name =
              line.speaker === "speaker1"
                ? (conversation.speaker1Name ?? "Speaker 1")
                : (conversation.speaker2Name ?? "Speaker 2");
            return `${name}: ${line.text}`;
          })
          .join("\n"),
        updatedAt: new Date(),
      })
      .where(eq(ttsProject.id, project.id));
    return conversation.lines;
  }

  const lines = await db.query.ttsDialogueLine.findMany({
    where: eq(ttsDialogueLine.projectId, project.id),
    orderBy: [asc(ttsDialogueLine.orderIndex)],
  });
  return lines
    .filter((l) => l.text.trim().length > 0)
    .map((l) => ({
      speaker: l.speaker as "speaker1" | "speaker2",
      text: l.text,
    }));
}

async function generateConversation(
  project: typeof ttsProject.$inferSelect,
  overrides?: { speaker1Voice?: string; speaker2Voice?: string }
) {
  const lines = await loadConversationLines(project);
  if (lines.length === 0) {
    throw new UserFacingError("Add at least one dialogue line.");
  }
  const speaker1Voice = overrides?.speaker1Voice ?? project.speaker1Voice;
  const speaker2Voice = overrides?.speaker2Voice ?? project.speaker2Voice;
  if (!speaker1Voice || !speaker2Voice) {
    throw new UserFacingError("Select a voice for both speakers.");
  }

  // project.model is provider-specific and may still hold a narration-mode
  // (OpenAI) model string if the track was switched to conversation mode
  // without regenerating a narration take first — always use the Gemini
  // default here rather than trusting it.
  const pcm = await synthesizeGeminiConversation({
    lines,
    speaker1Voice,
    speaker2Voice,
    model: GEMINI_TTS_DEFAULT_MODEL,
  });

  return {
    pcm,
    sampleRate: GEMINI_TTS_SAMPLE_RATE,
    voice: `${speaker1Voice}/${speaker2Voice}`,
    provider: "gemini",
    alignmentLines: lines.map((l) => l.text),
    contentHash: conversationContentHash(lines),
  };
}

class UserFacingError extends Error {}

const generateOverridesSchema = z
  .object({
    voice: z.string().optional(),
    provider: z.string().optional(),
    speaker1Voice: z.string().optional(),
    speaker2Voice: z.string().optional(),
  })
  .optional();

export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants">
) {
  const { id } = await ctx.params;

  const project = await db.query.ttsProject.findFirst({
    where: eq(ttsProject.id, id),
  });
  if (!project) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const rawBody = await request.text();
  const parsedOverrides = generateOverridesSchema.safeParse(
    rawBody ? JSON.parse(rawBody) : undefined
  );
  if (!parsedOverrides.success) {
    return NextResponse.json(
      { error: parsedOverrides.error.flatten() },
      { status: 400 }
    );
  }
  const overrides = parsedOverrides.data;

  let result: Awaited<ReturnType<typeof generateNarration>>;
  try {
    result =
      project.compositionMode === "conversation"
        ? await generateConversation(project, overrides)
        : await generateNarration(project, overrides);
  } catch (error) {
    const status = error instanceof UserFacingError ? 400 : 502;
    return NextResponse.json(
      { error: error instanceof Error ? error.message : String(error) },
      { status }
    );
  }

  const { pcm, sampleRate, voice, provider, alignmentLines, contentHash } =
    result;
  const wav = pcm16ToWav(pcm, sampleRate);
  const audioObjectKey = `tts/${id}/variants/${crypto.randomUUID()}.wav`;
  await putObject(audioObjectKey, wav, "audio/wav");

  const [variant] = await db
    .insert(ttsVariant)
    .values({
      projectId: id,
      audioObjectKey,
      sampleRate,
      audioByteCount: wav.length,
      voice,
      provider,
      contentHash,
    })
    .returning();

  const floatSamples = pcm16ToFloat32(pcm);
  const alignedLines = align(alignmentLines, floatSamples, sampleRate);
  if (alignedLines.length > 0) {
    await db.insert(ttsVariantSentence).values(
      alignedLines.map((line, index) => ({
        variantId: variant.id,
        index,
        text: line.text,
        sampleLower: line.sampleRange[0],
        sampleUpper: line.sampleRange[1],
      }))
    );
  }

  await db
    .update(ttsProject)
    .set({ selectedVariantId: variant.id, updatedAt: new Date() })
    .where(eq(ttsProject.id, id));

  return NextResponse.json({ variant }, { status: 201 });
}
