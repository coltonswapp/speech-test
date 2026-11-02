// Side-by-side voice takes for Settings → Voices (see lib/tts/voice-takes.ts):
// VOICE_TAKES_PER_VOICE takes of VOICE_TAKES_SAMPLE_TEXT for every voice in
// the Gemini voice catalog (30 Studio + ja-JP Tokyo library voices), on
// VOICE_TAKES_MODEL. Idempotent: existing takes are skipped.
//
//   Local only (no R2, no DB):
//     tsx scripts/seed-voice-takes.ts --local /workspace/gemini-tts-samples/voices
//   Upload to Studio's R2 bucket (R2_* env), reusing local takes when present:
//     pnpm db:seed-voice-takes --from /workspace/gemini-tts-samples/voices
//
// Writes only R2 objects under tts/voice-takes/<model>/ — never the database.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { GEMINI_VOICE_CATALOG } from "../lib/tts/gemini-voice-catalog";
import { buildGeminiSinglePayload } from "../lib/tts/gemini-tts-request";
import { geminiAudioToPcm16, pcm16ToWav } from "../lib/tts/wav";
import { estimateGeminiCostUSD } from "../lib/gemini/models";
import {
  VOICE_TAKES_MODEL,
  VOICE_TAKES_PER_VOICE,
  VOICE_TAKES_SAMPLE_TEXT,
  voiceTakesPrefix,
  voiceTakesManifestSchema,
  type VoiceTakesManifest,
} from "../lib/tts/voice-takes";

const SAMPLE_RATE = 24_000;
const args = process.argv.slice(2);
const argValue = (flag: string) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
};
const localDir = argValue("--local");
const fromDir = argValue("--from") ?? localDir;
const upload = !localDir;
const onlyVoices = argValue("--voices")?.split(",");

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const sha256 = (b: Buffer) => createHash("sha256").update(b).digest("hex");

let spentUSD = 0;
let generated = 0;

async function synthesize(voice: string): Promise<Buffer> {
  const apiKey = process.env.GEMINI_API_KEY?.trim();
  if (!apiKey) throw new Error("GEMINI_API_KEY is not set");
  for (let attempt = 0; attempt < 10; attempt++) {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${VOICE_TAKES_MODEL}:generateContent`,
      {
        method: "POST",
        headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
        body: JSON.stringify(buildGeminiSinglePayload({ text: VOICE_TAKES_SAMPLE_TEXT, voice })),
      }
    );
    if (res.status === 429 || res.status >= 500) {
      const body = await res.text();
      // Honor the API's RetryInfo when present; otherwise linear backoff.
      const hinted = /"retryDelay":\s*"(\d+(?:\.\d+)?)s"/.exec(body)?.[1];
      const quota = /"quotaId":\s*"([^"]+)"/.exec(body)?.[1];
      const wait = hinted ? Math.ceil(Number(hinted) + 1) * 1000 : 10_000 * (attempt + 1);
      console.log(
        `  ${voice}: HTTP ${res.status}${quota ? ` (${quota})` : ""}, retrying in ${wait / 1000}s`
      );
      await sleep(wait);
      continue;
    }
    if (!res.ok) throw new Error(`${voice}: HTTP ${res.status} ${(await res.text()).slice(0, 300)}`);
    const json = await res.json();
    const data = json?.candidates?.[0]?.content?.parts?.find(
      (p: { inlineData?: { data?: string } }) => p?.inlineData?.data
    )?.inlineData?.data;
    if (!data) throw new Error(`${voice}: no audio in response`);
    const usage = json.usageMetadata ?? {};
    spentUSD +=
      estimateGeminiCostUSD(
        VOICE_TAKES_MODEL,
        Number(usage.promptTokenCount ?? 0),
        Number(usage.candidatesTokenCount ?? 0)
      ) ?? 0;
    generated++;
    return pcm16ToWav(geminiAudioToPcm16(Buffer.from(data, "base64")), SAMPLE_RATE);
  }
  throw new Error(`${voice}: retries exhausted`);
}

async function main() {
  const r2 = upload ? await import("../lib/storage/standalone-r2") : null;
  const prefix = voiceTakesPrefix();
  const voices = GEMINI_VOICE_CATALOG.filter((v) => !onlyVoices || onlyVoices.includes(v.voice));
  const manifest: VoiceTakesManifest = {
    model: VOICE_TAKES_MODEL,
    sampleText: VOICE_TAKES_SAMPLE_TEXT,
    generatedAt: new Date().toISOString(),
    voices: [],
  };

  for (const entry of voices) {
    const takes: VoiceTakesManifest["voices"][number]["takes"] = [];
    const seen = new Set<string>();
    for (let take = 1; take <= VOICE_TAKES_PER_VOICE; take++) {
      const key = `${entry.voice}/take-${take}.wav`;
      const localPath = fromDir ? join(fromDir, key) : undefined;
      let wav: Buffer | undefined =
        localPath && existsSync(localPath) ? readFileSync(localPath) : undefined;

      if (upload && r2 && (await r2.objectExists(prefix + key))) {
        wav ??= await r2.getObject(prefix + key);
        console.log(`skip ${prefix + key} (already in R2)`);
      } else {
        const reused = Boolean(wav) && !seen.has(sha256(wav!));
        // Takes must differ from each other; regenerate an identical one.
        for (let tries = 0; !wav || seen.has(sha256(wav)); tries++) {
          if (tries >= 3) throw new Error(`${key}: could not get a unique take`);
          wav = await synthesize(entry.voice);
        }
        if (localPath && !reused) {
          mkdirSync(dirname(localPath), { recursive: true });
          writeFileSync(localPath, wav);
        }
        if (upload && r2) {
          await r2.putObject(prefix + key, wav, "audio/wav");
          console.log(`put ${prefix + key}`);
        } else {
          console.log(`${reused ? "keep" : "wrote"} ${localPath}`);
        }
      }
      seen.add(sha256(wav));
      takes.push({
        take,
        key,
        seconds: Number(((wav.length - 44) / (SAMPLE_RATE * 2)).toFixed(2)),
        bytes: wav.length,
        sha256: sha256(wav),
      });
    }
    manifest.voices.push({ voice: entry.voice, source: entry.source, takes });
  }

  const body = JSON.stringify(voiceTakesManifestSchema.parse(manifest), null, 1);
  if (fromDir) writeFileSync(join(fromDir, "manifest.json"), body);
  if (upload && r2) await r2.putObject(`${prefix}manifest.json`, Buffer.from(body), "application/json");
  console.log(
    `done: ${manifest.voices.length} voices, ${generated} new takes, ~$${spentUSD.toFixed(4)} at ${VOICE_TAKES_MODEL} rates`
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
