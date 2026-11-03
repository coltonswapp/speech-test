// Batch generation for voice takes (Settings → Voices → Voice takes).
// Pure: storage and synthesis are injected so the route stays thin and the
// skip / batch / quota rules are unit-tested (voice-takes-batch.test.ts).

import { createHash } from "node:crypto";
import {
  VOICE_TAKES_MODEL,
  VOICE_TAKES_PER_VOICE,
  VOICE_TAKES_SAMPLE_TEXT,
  type VoiceTakesManifest,
} from "@/lib/tts/voice-takes";
import { pcm16ToWav, wavToPcm16 } from "@/lib/tts/wav";

export type VoiceTakesManifestVoice = VoiceTakesManifest["voices"][number];
export type VoiceTakeEntry = VoiceTakesManifestVoice["takes"][number];

export type VoiceTakeStore = {
  readManifest(): Promise<VoiceTakesManifest | null>;
  writeManifest(manifest: VoiceTakesManifest): Promise<void>;
  /** Keys are relative to the takes root: `<voice>/take-<n>.wav`. */
  exists(key: string): Promise<boolean>;
  get(key: string): Promise<Buffer>;
  put(key: string, wav: Buffer): Promise<void>;
};

export type SynthesizeVoiceTake = (voice: string) => Promise<{ wav: Buffer; costUSD: number }>;

/** Gemini 429 / RESOURCE_EXHAUSTED. Stops the batch; nothing else does. */
export class VoiceTakeQuotaError extends Error {
  constructor(
    readonly retryAfterSeconds: number | null,
    readonly quotaId: string | null
  ) {
    super(`Gemini TTS quota reached${quotaId ? ` (${quotaId})` : ""}`);
  }

  get daily(): boolean {
    return /PerDay/i.test(this.quotaId ?? "");
  }
}

export type VoiceTakesBatchResult = {
  /** complete: every catalog voice has all takes. partial: more to do. quota: stopped on a quota hit. */
  status: "complete" | "partial" | "quota";
  manifest: VoiceTakesManifest;
  generatedTakes: number;
  costUSD: number;
  processedVoices: string[];
  failures: { voice: string; error: string }[];
  doneVoices: number;
  totalVoices: number;
  remainingVoices: number;
  quota: { retryAfterSeconds: number | null; quotaId: string | null; daily: boolean } | null;
};

export const takeKey = (voice: string, take: number) => `${voice}/take-${take}.wav`;
const sha256 = (b: Buffer) => createHash("sha256").update(b).digest("hex");
const WAV_HEADER_BYTES = 44;
const SAMPLE_RATE = 24_000;

function emptyManifest(now: Date): VoiceTakesManifest {
  return {
    model: VOICE_TAKES_MODEL,
    sampleText: VOICE_TAKES_SAMPLE_TEXT,
    generatedAt: now.toISOString(),
    voices: [],
  };
}

/** A stored manifest for another model or sample line is stale: start over. */
function currentManifest(stored: VoiceTakesManifest | null, now: Date): VoiceTakesManifest {
  if (!stored || stored.model !== VOICE_TAKES_MODEL || stored.sampleText !== VOICE_TAKES_SAMPLE_TEXT) {
    return emptyManifest(now);
  }
  return stored;
}

function isComplete(entry: VoiceTakesManifestVoice | undefined): boolean {
  if (!entry) return false;
  const have = new Set(entry.takes.map((t) => t.take));
  for (let take = 1; take <= VOICE_TAKES_PER_VOICE; take++) if (!have.has(take)) return false;
  return true;
}

function takeEntry(voice: string, take: number, wav: Buffer): VoiceTakeEntry {
  return {
    take,
    key: takeKey(voice, take),
    seconds: Number((Math.max(0, wav.length - WAV_HEADER_BYTES) / (SAMPLE_RATE * 2)).toFixed(2)),
    bytes: wav.length,
    sha256: sha256(wav),
  };
}

/**
 * Re-read the manifest (so a concurrent writer's voices aren't dropped), put
 * `entry` in catalog order, and write it. Shared by generate and upload.
 */
async function writeVoiceEntry(
  store: VoiceTakeStore,
  catalog: readonly { voice: string }[],
  entry: VoiceTakesManifestVoice,
  now: () => number
): Promise<VoiceTakesManifest> {
  const fresh = currentManifest(await store.readManifest(), new Date(now()));
  const order = new Map(catalog.map((v, i) => [v.voice, i]));
  const manifest: VoiceTakesManifest = {
    ...fresh,
    generatedAt: new Date(now()).toISOString(),
    voices: [...fresh.voices.filter((v) => v.voice !== entry.voice), entry].sort(
      (a, b) => (order.get(a.voice) ?? 1e9) - (order.get(b.voice) ?? 1e9)
    ),
  };
  await store.writeManifest(manifest);
  return manifest;
}

export async function runVoiceTakesBatch(params: {
  store: VoiceTakeStore;
  synthesize: SynthesizeVoiceTake;
  catalog: readonly { voice: string; source: "studio" | "library" }[];
  /** Voices to finish this call (each is VOICE_TAKES_PER_VOICE requests). */
  maxVoices: number;
  /** Only this voice. With force, its takes are regenerated even if present. */
  voice?: string;
  force?: boolean;
  /** Voices the caller already saw fail this session; skipped. */
  exclude?: readonly string[];
  /** Don't start another voice after this time (function time limit). */
  deadline?: number;
  now?: () => number;
}): Promise<VoiceTakesBatchResult> {
  const now = params.now ?? Date.now;
  const { store, catalog } = params;
  const exclude = new Set(params.exclude ?? []);
  let manifest = currentManifest(await store.readManifest(), new Date(now()));
  const entryOf = (m: VoiceTakesManifest, voice: string) => m.voices.find((v) => v.voice === voice);

  const targets = params.voice
    ? catalog.filter((v) => v.voice === params.voice)
    : catalog.filter((v) => !exclude.has(v.voice) && !isComplete(entryOf(manifest, v.voice)));
  const force = Boolean(params.voice && params.force);

  let generatedTakes = 0;
  let costUSD = 0;
  const processedVoices: string[] = [];
  const failures: VoiceTakesBatchResult["failures"] = [];
  let quota: VoiceTakeQuotaError | null = null;

  for (const target of targets.slice(0, Math.max(1, params.maxVoices))) {
    if (processedVoices.length > 0 && params.deadline !== undefined && now() >= params.deadline) break;
    const takes: VoiceTakeEntry[] = [];
    const seen = new Set<string>();
    try {
      for (let take = 1; take <= VOICE_TAKES_PER_VOICE; take++) {
        const key = takeKey(target.voice, take);
        let wav: Buffer | undefined;
        if (!force && (await store.exists(key))) {
          wav = await store.get(key);
        }
        // Takes must differ from each other; regenerate an identical one.
        for (let tries = 0; !wav || seen.has(sha256(wav)); tries++) {
          if (tries >= 3) throw new Error(`could not get a unique take ${take}`);
          const result = await params.synthesize(target.voice);
          wav = result.wav;
          costUSD += result.costUSD;
          generatedTakes++;
          await store.put(key, wav);
        }
        seen.add(sha256(wav));
        takes.push(takeEntry(target.voice, take, wav));
      }
    } catch (error) {
      if (error instanceof VoiceTakeQuotaError) quota = error;
      else failures.push({ voice: target.voice, error: (error as Error).message });
    }

    if (takes.length > 0) {
      manifest = await writeVoiceEntry(store, catalog, { voice: target.voice, source: target.source, takes }, now);
    }
    processedVoices.push(target.voice);
    if (quota) break;
  }

  const doneVoices = catalog.filter((v) => isComplete(entryOf(manifest, v.voice))).length;
  const remainingVoices = catalog.length - doneVoices;
  return {
    status: quota ? "quota" : remainingVoices === 0 ? "complete" : "partial",
    manifest,
    generatedTakes,
    costUSD,
    processedVoices,
    failures,
    doneVoices,
    totalVoices: catalog.length,
    remainingVoices,
    quota: quota
      ? { retryAfterSeconds: quota.retryAfterSeconds, quotaId: quota.quotaId, daily: quota.daily }
      : null,
  };
}

/** Parse Gemini's 429 body (google.rpc RetryInfo / QuotaFailure). */
export function parseGeminiQuotaError(body: string): VoiceTakeQuotaError {
  const delay = /"retryDelay":\s*"(\d+(?:\.\d+)?)s"/.exec(body)?.[1];
  const quotaId = /"quotaId":\s*"([^"]+)"/.exec(body)?.[1] ?? null;
  return new VoiceTakeQuotaError(delay ? Math.ceil(Number(delay)) : null, quotaId);
}

export class VoiceTakeUploadError extends Error {
  constructor(
    message: string,
    readonly status: 400 | 409
  ) {
    super(message);
  }
}

/**
 * Only the exact WAV the generate path writes (pcm16ToWav: 44-byte header,
 * 24 kHz mono 16-bit PCM) is accepted, so `seconds` and playback match.
 * Conversion happens before upload, never here.
 */
export function assertStoredTakeFormat(wav: Buffer): void {
  let parsed: { pcm: Buffer; sampleRate: number };
  try {
    parsed = wavToPcm16(wav);
  } catch (error) {
    throw new VoiceTakeUploadError((error as Error).message, 400);
  }
  if (parsed.sampleRate !== SAMPLE_RATE || !pcm16ToWav(parsed.pcm, SAMPLE_RATE).equals(wav)) {
    throw new VoiceTakeUploadError(
      "Expected a 44-byte-header 24 kHz mono 16-bit PCM WAV (the format generate stores).",
      400
    );
  }
  if (parsed.pcm.length === 0) throw new VoiceTakeUploadError("WAV has no audio.", 400);
}

export type VoiceTakeUploadResult = {
  status: "stored" | "skipped";
  voice: string;
  take: number;
  key: string;
  entry: VoiceTakeEntry;
  manifest: VoiceTakesManifest;
};

/**
 * Store one pre-generated take under the same key and manifest entry the
 * batch writes, so the player and "Generate missing takes" treat it as done.
 * An existing take is left alone (status "skipped") unless overwrite is set.
 */
export async function uploadVoiceTake(params: {
  store: VoiceTakeStore;
  catalog: readonly { voice: string; source: "studio" | "library" }[];
  voice: string;
  take: number;
  model: string;
  wav: Buffer;
  overwrite?: boolean;
  now?: () => number;
}): Promise<VoiceTakeUploadResult> {
  const now = params.now ?? Date.now;
  const { store, catalog, voice, take, wav } = params;
  const target = catalog.find((v) => v.voice === voice);
  if (!target) throw new VoiceTakeUploadError("Unknown voice", 400);
  if (!Number.isInteger(take) || take < 1 || take > VOICE_TAKES_PER_VOICE) {
    throw new VoiceTakeUploadError(`take must be 1..${VOICE_TAKES_PER_VOICE}`, 400);
  }
  if (params.model !== VOICE_TAKES_MODEL) {
    throw new VoiceTakeUploadError(`model must be ${VOICE_TAKES_MODEL}`, 400);
  }
  assertStoredTakeFormat(wav);

  const key = takeKey(voice, take);
  const stored = currentManifest(await store.readManifest(), new Date(now()));
  const existing = stored.voices.find((v) => v.voice === voice);
  const listed = existing?.takes.find((t) => t.take === take);

  if (!params.overwrite && (await store.exists(key))) {
    // Already stored: make sure the manifest lists it (as the batch would), then skip.
    const entry = listed ?? takeEntry(voice, take, await store.get(key));
    const manifest = listed
      ? stored
      : await writeVoiceEntry(store, catalog, withTake(existing, target, entry), now);
    return { status: "skipped", voice, take, key, entry, manifest };
  }

  const entry = takeEntry(voice, take, wav);
  // Takes of one voice must differ, same rule as generate.
  if (existing?.takes.some((t) => t.take !== take && t.sha256 === entry.sha256)) {
    throw new VoiceTakeUploadError("Identical to another take of this voice", 409);
  }
  await store.put(key, wav);
  const manifest = await writeVoiceEntry(store, catalog, withTake(existing, target, entry), now);
  return { status: "stored", voice, take, key, entry, manifest };
}

function withTake(
  existing: VoiceTakesManifestVoice | undefined,
  target: { voice: string; source: "studio" | "library" },
  entry: VoiceTakeEntry
): VoiceTakesManifestVoice {
  const takes = [...(existing?.takes ?? []).filter((t) => t.take !== entry.take), entry].sort(
    (a, b) => a.take - b.take
  );
  return { voice: target.voice, source: target.source, takes };
}
