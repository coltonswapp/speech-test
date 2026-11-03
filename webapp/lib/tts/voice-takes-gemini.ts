import "server-only";
import { getProviderKey } from "@/lib/secrets";
import { estimateGeminiCostUSD } from "@/lib/gemini/models";
import { buildGeminiSinglePayload } from "@/lib/tts/gemini-tts-request";
import { geminiAudioToPcm16, pcm16ToWav } from "@/lib/tts/wav";
import { getObject, objectExists, putObject } from "@/lib/storage/r2";
import {
  VOICE_TAKES_MODEL,
  VOICE_TAKES_SAMPLE_TEXT,
  voiceTakesManifestKey,
  voiceTakesManifestSchema,
  voiceTakesPrefix,
  type VoiceTakesManifest,
} from "@/lib/tts/voice-takes";
import {
  parseGeminiQuotaError,
  type SynthesizeVoiceTake,
  type VoiceTakeStore,
} from "@/lib/tts/voice-takes-batch";

const SAMPLE_RATE = 24_000;

function isMissingObject(error: unknown): boolean {
  const e = error as { name?: string; $metadata?: { httpStatusCode?: number } };
  return e?.name === "NoSuchKey" || e?.$metadata?.httpStatusCode === 404;
}

export async function readVoiceTakesManifest(): Promise<VoiceTakesManifest | null> {
  try {
    const raw = await getObject(voiceTakesManifestKey());
    const parsed = voiceTakesManifestSchema.safeParse(JSON.parse(raw.toString("utf8")));
    return parsed.success ? parsed.data : null;
  } catch (error) {
    if (isMissingObject(error)) return null;
    throw error;
  }
}

/** Studio's normal R2 bucket, under tts/voice-takes/<model>/. */
export const r2VoiceTakeStore: VoiceTakeStore = {
  readManifest: readVoiceTakesManifest,
  writeManifest: (manifest) =>
    putObject(
      voiceTakesManifestKey(),
      Buffer.from(JSON.stringify(voiceTakesManifestSchema.parse(manifest))),
      "application/json"
    ),
  exists: (key) => objectExists(voiceTakesPrefix() + key),
  get: (key) => getObject(voiceTakesPrefix() + key),
  put: (key, wav) => putObject(voiceTakesPrefix() + key, wav, "audio/wav"),
};

export class VoiceTakeConfigError extends Error {}

/** One take of the sample line on VOICE_TAKES_MODEL. 429 → VoiceTakeQuotaError. */
export const synthesizeVoiceTake: SynthesizeVoiceTake = async (voice) => {
  const apiKey = getProviderKey("gemini");
  if (!apiKey) throw new VoiceTakeConfigError("Missing Gemini API key.");
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${VOICE_TAKES_MODEL}:generateContent`,
      {
        method: "POST",
        headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
        body: JSON.stringify(buildGeminiSinglePayload({ text: VOICE_TAKES_SAMPLE_TEXT, voice })),
      }
    );
    if (res.status === 429) throw parseGeminiQuotaError(await res.text());
    // One quick retry on a transient server error, then report it.
    if (res.status >= 500 && attempt === 0) {
      await new Promise((r) => setTimeout(r, 2000));
      continue;
    }
    if (!res.ok) {
      throw new Error(`Gemini HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
    }
    const json = await res.json();
    const data = json?.candidates?.[0]?.content?.parts?.find(
      (p: { inlineData?: { data?: string } }) => p?.inlineData?.data
    )?.inlineData?.data;
    if (!data) throw new Error("Gemini returned no audio.");
    const usage = json.usageMetadata ?? {};
    const costUSD =
      estimateGeminiCostUSD(
        VOICE_TAKES_MODEL,
        Number(usage.promptTokenCount ?? 0),
        Number(usage.candidatesTokenCount ?? 0)
      ) ?? 0;
    return { wav: pcm16ToWav(geminiAudioToPcm16(Buffer.from(data, "base64")), SAMPLE_RATE), costUSD };
  }
};
