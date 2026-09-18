import { NextResponse, after } from "next/server";
import type { NextRequest } from "next/server";
import { desc, eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ttsProject, ttsVariant, ttsVariantSentence } from "@/lib/db/schema";
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
import { loadConversationLines, UserFacingError } from "@/lib/tts/project-lines";
import { alignerConfigured } from "@/lib/aligner/client";
import {
  getAutoStampJobs,
  runAutoStampChain,
  setAutoStampJob,
} from "@/lib/dialogue/auto-stamp";

// Generation plus the post-response auto-stamp chain (tokenize + align) can
// take a few minutes on an uncached script.
export const maxDuration = 300;

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants">
) {
  const { id } = await ctx.params;
  const rows = await db.query.ttsVariant.findMany({
    where: eq(ttsVariant.projectId, id),
    orderBy: [desc(ttsVariant.createdAt)],
  });
  const jobs = await getAutoStampJobs(rows.map((v) => v.id));
  const variants = rows.map((variant) => ({
    ...variant,
    autoStampJob: jobs.get(variant.id) ?? null,
  }));
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
    speaker1Name: project.speaker1Name,
    speaker2Name: project.speaker2Name,
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

  // Do not auto-select the newest take — selection stays an explicit user
  // action in the Takes UI ("Use this take").
  await db
    .update(ttsProject)
    .set({ updatedAt: new Date() })
    .where(eq(ttsProject.id, id));

  // KA-7: tokenize (cached) + align after the response is sent, so a fresh
  // take arrives in Studio already stamped and flagged. Conversation takes
  // only — narration has no per-line karaoke.
  const chain = project.compositionMode === "conversation" && alignerConfigured();
  const queuedAt = new Date().toISOString();
  if (chain) {
    await setAutoStampJob(variant.id, {
      status: "queued",
      startedAt: queuedAt,
    });
    after(() => runAutoStampChain(variant.id));
  }

  return NextResponse.json(
    {
      variant: {
        ...variant,
        autoStampJob: chain
          ? { status: "queued", startedAt: queuedAt, updatedAt: queuedAt }
          : null,
      },
    },
    { status: 201 }
  );
}
