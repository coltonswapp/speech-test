import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseGeminiQuotaError,
  runVoiceTakesBatch,
  takeKey,
  uploadVoiceTake,
  VoiceTakeQuotaError,
  VoiceTakeUploadError,
  type VoiceTakeStore,
} from "./voice-takes-batch";
import { VOICE_TAKES_MODEL, VOICE_TAKES_PER_VOICE, type VoiceTakesManifest } from "./voice-takes";
import { pcm16ToWav } from "./wav";

const catalog = ["A", "B", "C", "D", "E"].map((voice) => ({ voice, source: "studio" as const }));

function memoryStore(seed: Record<string, Buffer> = {}) {
  const objects = new Map(Object.entries(seed));
  let manifest: VoiceTakesManifest | null = null;
  const store: VoiceTakeStore = {
    readManifest: async () => manifest,
    writeManifest: async (m) => void (manifest = m),
    exists: async (k) => objects.has(k),
    get: async (k) => objects.get(k)!,
    put: async (k, wav) => void objects.set(k, wav),
  };
  return { store, objects, manifest: () => manifest };
}

let counter = 0;
const wav = () => Buffer.concat([Buffer.alloc(44), Buffer.from(`pcm-${counter++}`)]);
function synth(failOn: Record<string, Error> = {}) {
  const calls: string[] = [];
  return {
    calls,
    fn: async (voice: string) => {
      calls.push(voice);
      if (failOn[voice]) throw failOn[voice];
      return { wav: wav(), costUSD: 0.001 };
    },
  };
}

test("generates missing voices in batches and skips existing takes", async () => {
  const mem = memoryStore({ [takeKey("A", 1)]: wav(), [takeKey("A", 2)]: wav() });
  const s = synth();
  const first = await runVoiceTakesBatch({ store: mem.store, synthesize: s.fn, catalog, maxVoices: 2 });
  // A was already in storage (no manifest yet): reused, not regenerated.
  assert.deepEqual(first.processedVoices, ["A", "B"]);
  assert.deepEqual(s.calls, ["B", "B"]);
  assert.equal(first.generatedTakes, VOICE_TAKES_PER_VOICE);
  assert.equal(first.status, "partial");
  assert.equal(first.doneVoices, 2);
  assert.equal(first.remainingVoices, 3);

  const second = await runVoiceTakesBatch({ store: mem.store, synthesize: s.fn, catalog, maxVoices: 10 });
  assert.deepEqual(second.processedVoices, ["C", "D", "E"]);
  assert.equal(second.status, "complete");
  assert.deepEqual(mem.manifest()!.voices.map((v) => v.voice), ["A", "B", "C", "D", "E"]);

  const third = await runVoiceTakesBatch({ store: mem.store, synthesize: s.fn, catalog, maxVoices: 10 });
  assert.equal(third.generatedTakes, 0);
  assert.equal(third.status, "complete");
});

test("quota hit stops cleanly, keeps progress, and returns the retry hint", async () => {
  const mem = memoryStore();
  const s = synth({ C: new VoiceTakeQuotaError(29338, "GenerateRequestsPerDayPerProjectPerModel") });
  const result = await runVoiceTakesBatch({ store: mem.store, synthesize: s.fn, catalog, maxVoices: 4 });
  assert.equal(result.status, "quota");
  assert.deepEqual(result.quota, {
    retryAfterSeconds: 29338,
    quotaId: "GenerateRequestsPerDayPerProjectPerModel",
    daily: true,
  });
  assert.deepEqual(result.processedVoices, ["A", "B", "C"]);
  assert.equal(result.doneVoices, 2);
  assert.equal(result.remainingVoices, 3);
  assert.equal(s.calls.includes("D"), false);
});

test("other failures are reported per voice without failing the batch; exclude skips them", async () => {
  const mem = memoryStore();
  const s = synth({ B: new Error("Gemini HTTP 400") });
  const result = await runVoiceTakesBatch({ store: mem.store, synthesize: s.fn, catalog, maxVoices: 3 });
  assert.deepEqual(result.failures, [{ voice: "B", error: "Gemini HTTP 400" }]);
  assert.equal(result.doneVoices, 2);
  const next = await runVoiceTakesBatch({
    store: mem.store,
    synthesize: s.fn,
    catalog,
    maxVoices: 3,
    exclude: ["B"],
  });
  assert.deepEqual(next.processedVoices, ["D", "E"]);
});

test("force regenerates one voice; duplicate takes are retried; deadline caps the batch", async () => {
  const mem = memoryStore();
  await runVoiceTakesBatch({ store: mem.store, synthesize: synth().fn, catalog, maxVoices: 1 });
  const before = mem.manifest()!.voices[0].takes.map((t) => t.sha256);
  const forced = await runVoiceTakesBatch({
    store: mem.store,
    synthesize: synth().fn,
    catalog,
    maxVoices: 5,
    voice: "A",
    force: true,
  });
  assert.deepEqual(forced.processedVoices, ["A"]);
  const after = mem.manifest()!.voices[0].takes.map((t) => t.sha256);
  assert.notDeepEqual(after, before);

  const same = Buffer.concat([Buffer.alloc(44), Buffer.from("same")]);
  let n = 0;
  const dupes = await runVoiceTakesBatch({
    store: memoryStore().store,
    synthesize: async () => ({ wav: n++ < 2 ? same : wav(), costUSD: 0 }),
    catalog,
    maxVoices: 1,
  });
  const takes = dupes.manifest.voices[0].takes;
  assert.notEqual(takes[0].sha256, takes[1].sha256);

  let clock = 0;
  const capped = await runVoiceTakesBatch({
    store: memoryStore().store,
    synthesize: async () => ((clock += 100), { wav: wav(), costUSD: 0 }),
    catalog,
    maxVoices: 5,
    deadline: 150,
    now: () => clock,
  });
  assert.deepEqual(capped.processedVoices, ["A"]);
});

test("parses Gemini 429 RetryInfo and QuotaFailure", () => {
  const err = parseGeminiQuotaError(
    JSON.stringify({
      error: {
        code: 429,
        details: [
          { violations: [{ quotaId: "GenerateRequestsPerMinutePerProjectPerModel" }] },
          { retryDelay: "12.5s" },
        ],
      },
    })
  );
  assert.equal(err.retryAfterSeconds, 13);
  assert.equal(err.daily, false);
  assert.equal(parseGeminiQuotaError("{}").retryAfterSeconds, null);
});

const realWav = (seed: number, samples = 2400) =>
  pcm16ToWav(Buffer.alloc(samples * 2, seed), 24_000);
const upload = (store: VoiceTakeStore, voice: string, take: number, wav: Buffer, overwrite = false) =>
  uploadVoiceTake({ store, catalog, voice, take, model: VOICE_TAKES_MODEL, wav, overwrite });

test("uploaded takes land on generate's keys and manifest, so the batch skips them", async () => {
  const mem = memoryStore();
  const first = await upload(mem.store, "B", 1, realWav(1));
  assert.equal(first.status, "stored");
  assert.equal(first.key, takeKey("B", 1));
  assert.equal(first.entry.seconds, 0.1);
  assert.equal(first.entry.bytes, 44 + 4800);
  await upload(mem.store, "B", 2, realWav(2));
  await upload(mem.store, "A", 2, realWav(3));
  await upload(mem.store, "A", 1, realWav(4));
  const m = mem.manifest()!;
  assert.equal(m.model, VOICE_TAKES_MODEL);
  // Catalog order for voices, take order within a voice.
  assert.deepEqual(m.voices.map((v) => v.voice), ["A", "B"]);
  assert.deepEqual(m.voices[0].takes.map((t) => t.take), [1, 2]);
  assert.equal(m.voices[0].source, "studio");

  const s = synth();
  const batch = await runVoiceTakesBatch({ store: mem.store, synthesize: s.fn, catalog, maxVoices: 10 });
  assert.deepEqual(batch.processedVoices, ["C", "D", "E"]);
  assert.equal(s.calls.includes("A") || s.calls.includes("B"), false);
  assert.equal(batch.status, "complete");
});

test("upload is idempotent: existing takes skip unless overwrite", async () => {
  const mem = memoryStore();
  const original = realWav(1);
  await upload(mem.store, "A", 1, original);
  const skipped = await upload(mem.store, "A", 1, realWav(9));
  assert.equal(skipped.status, "skipped");
  assert.ok(mem.objects.get(takeKey("A", 1))!.equals(original));

  const replaced = await upload(mem.store, "A", 1, realWav(9), true);
  assert.equal(replaced.status, "stored");
  assert.ok(mem.objects.get(takeKey("A", 1))!.equals(realWav(9)));
  assert.equal(mem.manifest()!.voices[0].takes.length, 1);

  // An object already in storage but missing from the manifest is listed, not rewritten.
  const seeded = memoryStore({ [takeKey("C", 2)]: realWav(5) });
  const listed = await upload(seeded.store, "C", 2, realWav(6));
  assert.equal(listed.status, "skipped");
  assert.deepEqual(seeded.manifest()!.voices.map((v) => [v.voice, v.takes.map((t) => t.take)]), [["C", [2]]]);
});

test("upload rejects unknown voices, bad takes, other models, wrong formats, duplicate takes", async () => {
  const { store } = memoryStore();
  const rejects = (p: Promise<unknown>, status: number, match: RegExp) =>
    assert.rejects(p, (e: unknown) => e instanceof VoiceTakeUploadError && e.status === status && match.test(e.message));
  await rejects(upload(store, "Nope", 1, realWav(1)), 400, /Unknown voice/);
  await rejects(upload(store, "A", 0, realWav(1)), 400, /take must be/);
  await rejects(upload(store, "A", VOICE_TAKES_PER_VOICE + 1, realWav(1)), 400, /take must be/);
  await rejects(
    uploadVoiceTake({ store, catalog, voice: "A", take: 1, model: "gemini-3.1-flash-tts-preview", wav: realWav(1) }),
    400,
    /model must be/
  );
  await rejects(upload(store, "A", 1, Buffer.from("not a wav at all, definitely not")), 400, /Not a WAV/);
  await rejects(upload(store, "A", 1, pcm16ToWav(Buffer.alloc(4800, 1), 44_100)), 400, /24 kHz/);
  // Extra chunk after data (e.g. raw Gemini 3.8 output with C2PA) is not the stored format.
  await rejects(upload(store, "A", 1, Buffer.concat([realWav(1), Buffer.from("c2pa\x04\0\0\0abcd")])), 400, /24 kHz/);
  await rejects(upload(store, "A", 1, pcm16ToWav(Buffer.alloc(0), 24_000)), 400, /no audio|24 kHz/);

  await upload(store, "A", 1, realWav(7));
  await rejects(upload(store, "A", 2, realWav(7)), 409, /Identical/);
});
