import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { isProviderConfigured } from "@/lib/secrets";
import { GEMINI_VOICE_CATALOG, geminiVoiceEntry } from "@/lib/tts/gemini-voice-catalog";
import { runVoiceTakesBatch } from "@/lib/tts/voice-takes-batch";
import { r2VoiceTakeStore, synthesizeVoiceTake } from "@/lib/tts/voice-takes-gemini";

// Auth: proxy.ts gates every non-public /api route (passphrase, Google
// session, or API bearer), same as the other Studio TTS routes.

// Each voice is VOICE_TAKES_PER_VOICE sequential TTS calls (~3–8 s each).
// A batch stops starting new voices after BATCH_BUDGET_MS so it finishes well
// inside maxDuration; the client loops batches until done or a quota hit.
export const maxDuration = 300;
const BATCH_BUDGET_MS = 180_000;
const DEFAULT_BATCH_VOICES = 4;

const bodySchema = z
  .object({
    voice: z.string().optional(),
    force: z.boolean().optional(),
    maxVoices: z.number().int().min(1).max(10).optional(),
    exclude: z.array(z.string()).max(200).optional(),
  })
  .refine((b) => !b.force || b.voice, { message: "force needs a voice" })
  .refine((b) => !b.voice || geminiVoiceEntry(b.voice), { message: "Unknown voice" });

/**
 * Generate missing voice takes in one small batch: skips takes already in R2,
 * writes new WAVs plus the manifest. A Gemini quota hit stops the batch and
 * returns status "quota" with the retry hint (HTTP 200, progress kept).
 */
export async function POST(request: NextRequest) {
  const parsed = bodySchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  if (!isProviderConfigured("gemini")) {
    return NextResponse.json({ error: "Missing Gemini API key." }, { status: 400 });
  }
  const started = Date.now();
  const result = await runVoiceTakesBatch({
    store: r2VoiceTakeStore,
    synthesize: synthesizeVoiceTake,
    catalog: GEMINI_VOICE_CATALOG,
    maxVoices: parsed.data.voice ? 1 : (parsed.data.maxVoices ?? DEFAULT_BATCH_VOICES),
    voice: parsed.data.voice,
    force: parsed.data.force,
    exclude: parsed.data.exclude,
    deadline: started + BATCH_BUDGET_MS,
  });
  return NextResponse.json(result);
}
