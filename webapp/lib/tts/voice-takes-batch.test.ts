import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseGeminiQuotaError,
  runVoiceTakesBatch,
  takeKey,
  VoiceTakeQuotaError,
  type VoiceTakeStore,
} from "./voice-takes-batch";
import { VOICE_TAKES_PER_VOICE, type VoiceTakesManifest } from "./voice-takes";

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
