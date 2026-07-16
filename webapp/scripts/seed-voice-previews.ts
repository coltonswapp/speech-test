// Generates one short preview clip per TTS voice so the voice picker can
// play a cached sample instead of round-tripping to the provider on every
// click. Run with: pnpm db:seed-voice-previews (add --force to regenerate
// voices that already have a preview row).
//
// Idempotent — skips voices that already have a row unless --force is
// passed, safe to re-run after the voice catalog changes.

import { eq, and } from "drizzle-orm";
import { db } from "../lib/db/standalone-client";
import { voicePreview } from "../lib/db/schema";
import { putObject } from "../lib/storage/standalone-r2";
import { pcm16ToWav } from "../lib/tts/wav";
import {
  synthesizeOpenAIStandalone,
  synthesizeGeminiSingleStandalone,
  OPENAI_STANDALONE_SAMPLE_RATE,
  GEMINI_STANDALONE_SAMPLE_RATE,
} from "../lib/tts/standalone-synthesize";
import { OPENAI_VOICES } from "../lib/tts/voices";
import { GEMINI_TTS_VOICES } from "../lib/tts/gemini-voices";

const SAMPLE_TEXT = "今日はいい天気ですね。";

const force = process.argv.includes("--force");

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function alreadyHasPreview(provider: string, voice: string) {
  const existing = await db.query.voicePreview.findFirst({
    where: and(eq(voicePreview.provider, provider), eq(voicePreview.voice, voice)),
  });
  return Boolean(existing);
}

// Gemini's TTS preview model is rate-limited to 10 requests/minute, so retry
// once on 429 after the delay it reports rather than aborting the whole run.
async function synthesizeWithRetry(synthesize: () => Promise<Buffer>) {
  try {
    return await synthesize();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes("HTTP 429")) throw error;
    console.log("Rate limited, waiting 40s before retrying...");
    await sleep(40_000);
    return synthesize();
  }
}

async function generateOne(
  provider: "openai" | "gemini",
  voice: string,
  synthesize: () => Promise<Buffer>,
  sampleRate: number
) {
  if (!force && (await alreadyHasPreview(provider, voice))) {
    console.log(`Skipping ${provider}/${voice} (already exists).`);
    return;
  }

  console.log(`Generating ${provider}/${voice}...`);
  const pcm = await synthesizeWithRetry(synthesize);
  const wav = pcm16ToWav(pcm, sampleRate);
  const audioObjectKey = `tts/_previews/${provider}/${voice}.wav`;
  await putObject(audioObjectKey, wav, "audio/wav");

  await db
    .insert(voicePreview)
    .values({ provider, voice, audioObjectKey, sampleRate })
    .onConflictDoUpdate({
      target: [voicePreview.provider, voicePreview.voice],
      set: { audioObjectKey, sampleRate },
    });
}

async function main() {
  for (const voice of OPENAI_VOICES) {
    await generateOne(
      "openai",
      voice,
      () => synthesizeOpenAIStandalone({ text: SAMPLE_TEXT, voice }),
      OPENAI_STANDALONE_SAMPLE_RATE
    );
  }

  for (const voice of GEMINI_TTS_VOICES) {
    await generateOne(
      "gemini",
      voice,
      () => synthesizeGeminiSingleStandalone({ text: SAMPLE_TEXT, voice }),
      GEMINI_STANDALONE_SAMPLE_RATE
    );
    // Stay under Gemini's 10 requests/minute quota for this model.
    await sleep(7_000);
  }

  console.log("Done.");
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
