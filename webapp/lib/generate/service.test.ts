import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { pcm16ToWav, wavToPcm16 } from "@/lib/tts/wav";
import { GEMINI_TTS_VOICES } from "@/lib/tts/gemini-voices";
import {
  alignGeneration,
  cleanupExpiredGenerations,
  createTtsGeneration,
  deleteGeneration,
  getPlayableMp3,
  listGenerations,
  saveGeneration,
  type GenerateService,
} from "./service";
import { memoryGenerationStore, type GenerationStore } from "./store";
import { GENERATE_R2_PREFIX, generateMp3Key, generateWavKey } from "./keys";
import {
  GENERATE_PENDING_STALE_MS,
  GENERATE_TEMPORARY_TTL_MS,
  type GenerationRecord,
} from "./types";
import { GenerateUserError } from "./validate";
import { isMpegAudio, silencePcm16 } from "./compose";
import type { GenerationClaim } from "./claims";

const RATE = 24_000;
const VOICE = GEMINI_TTS_VOICES[0];

function pcm(samples: number, value = 1200): Buffer {
  const buf = Buffer.alloc(samples * 2);
  for (let i = 0; i < samples; i++) buf.writeInt16LE(value, i * 2);
  return buf;
}

function fakeMp3(wav: Buffer): Buffer {
  return Buffer.concat([Buffer.from("ID3"), wav.subarray(0, 16)]);
}

function testService(overrides: Partial<GenerateService> = {}): GenerateService & {
  objectsMap: Map<string, Buffer>;
  synthCalls: number;
} {
  const objectsMap = new Map<string, Buffer>();
  const synthCalls = { n: 0 };
  const svc: GenerateService & {
    objectsMap: Map<string, Buffer>;
    synthCalls: number;
  } = {
    store: memoryGenerationStore(),
    objects: {
      async put(key, body) {
        objectsMap.set(key, Buffer.from(body));
      },
      async get(key) {
        const body = objectsMap.get(key);
        if (!body) throw new Error(`missing ${key}`);
        return body;
      },
      async delete(key) {
        objectsMap.delete(key);
      },
    },
    tts: {
      sampleRate: RATE,
      async synthesizeLine() {
        synthCalls.n += 1;
        return pcm(RATE); // 1s
      },
    },
    encoder: {
      async encodeWavToMp3(wav) {
        return fakeMp3(wav);
      },
      async transcodeToWavMono(audio) {
        return audio;
      },
    },
    aligner: {
      configured: () => true,
      async align() {
        return {
          alignerVersion: "mms-fa-v1.1",
          durationSeconds: 1,
          sampleRate: RATE,
          lines: [
            {
              tokens: [
                { startSeconds: 0.1, endSeconds: 0.4, score: 0.9, readingFallback: false },
                { startSeconds: 0.4, endSeconds: 0.8, score: 0.9, readingFallback: false },
              ],
              score: 0.9,
            },
          ],
        };
      },
    },
    tokenizer: {
      async tokenize(texts) {
        return texts.map((text) => ({
          text,
          tokens: text.split("").filter(Boolean).map((ch) => ({ text: ch })),
        }));
      },
    },
    now: () => new Date("2026-11-07T00:00:00.000Z"),
    randomId: () => "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    objectsMap,
    get synthCalls() {
      return synthCalls.n;
    },
    ...overrides,
  };
  if (overrides.objects) svc.objects = overrides.objects;
  if (overrides.tts) svc.tts = overrides.tts;
  if (overrides.store) svc.store = overrides.store;
  return svc;
}

describe("createTtsGeneration", () => {
  it("stores a real MP3 under tts/generate and keeps the clip unsaved", async () => {
    const svc = testService();
    const { generation, reused } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      lines: [{ id: "1", text: "こんにちは", voice: VOICE }],
    });
    assert.equal(reused, false);
    assert.equal(generation.savedAt, null);
    assert.ok(generation.mp3ObjectKey?.startsWith(GENERATE_R2_PREFIX));
    assert.ok(generation.wavObjectKey?.startsWith(GENERATE_R2_PREFIX));
    const mp3 = svc.objectsMap.get(generation.mp3ObjectKey!);
    assert.ok(mp3 && isMpegAudio(mp3));
    assert.equal(generation.durationSeconds, 1);
  });

  it("preserves order and pauses across multiple voices", async () => {
    const second = GEMINI_TTS_VOICES[1];
    const svc = testService({
      tts: {
        sampleRate: RATE,
        async synthesizeLine({ voice }) {
          return voice === VOICE ? pcm(RATE) : pcm(RATE / 2);
        },
      },
    });
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      lines: [
        { id: "1", text: "いち", voice: VOICE, pauseAfterSeconds: 0.5 },
        { id: "2", text: "に", voice: second },
      ],
    });
    assert.equal(generation.durationSeconds, 2);
    assert.equal(generation.lineTimings?.[0].endSeconds, 1);
    assert.equal(generation.lineTimings?.[1].startSeconds, 1.5);
    const wav = svc.objectsMap.get(generation.wavObjectKey!);
    assert.ok(wav);
    const { pcm: combined } = wavToPcm16(wav);
    const pause = combined.subarray(RATE * 2, RATE * 2 + Math.round(0.5 * RATE) * 2);
    assert.ok(pause.every((byte) => byte === 0));
  });

  it("is idempotent on requestId and does not resynthesize", async () => {
    const svc = testService();
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    const first = await createTtsGeneration(svc, input);
    const second = await createTtsGeneration(svc, input);
    assert.equal(second.reused, true);
    assert.equal(second.generation.id, first.generation.id);
    assert.equal(svc.synthCalls, 1);
  });

  it("regenerates when the client sends a new request id", async () => {
    let n = 0;
    const svc = testService({
      randomId: () =>
        `aaaaaaaa-aaaa-aaaa-aaaa-${String(++n).padStart(12, "0")}`,
    });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    const first = await createTtsGeneration(svc, {
      ...input,
      requestId: "cccccccc-cccc-cccc-cccc-cccccccccccc",
    });
    const second = await createTtsGeneration(svc, {
      ...input,
      requestId: "dddddddd-dddd-dddd-dddd-dddddddddddd",
    });
    assert.equal(second.reused, false);
    assert.notEqual(second.generation.id, first.generation.id);
    assert.equal(svc.synthCalls, 2);
  });

  it("surfaces a TTS failure as a failed reservation without objects", async () => {
    const svc = testService({
      tts: {
        sampleRate: RATE,
        async synthesizeLine() {
          throw new Error("Gemini request failed (HTTP 502): boom");
        },
      },
    });
    await assert.rejects(
      () =>
        createTtsGeneration(svc, {
          model: "gemini-3.8-flash-tts",
          requestId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
          lines: [{ id: "1", text: "はい", voice: VOICE }],
        }),
      /502/,
    );
    const rows = await svc.store.list();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].status, "failed");
    assert.equal(svc.objectsMap.size, 0);
  });

  it("rejects an unknown voice before calling TTS", async () => {
    const svc = testService();
    await assert.rejects(
      () =>
        createTtsGeneration(svc, {
          model: "gemini-3.8-flash-tts",
          requestId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
          lines: [{ id: "1", text: "はい", voice: "Nope" }],
        }),
      GenerateUserError,
    );
    assert.equal(svc.synthCalls, 0);
    assert.deepEqual(await svc.store.list(), []);
  });
});

describe("save and delete", () => {
  it("save is idempotent and delete only removes generate objects", async () => {
    const svc = testService();
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    });
    const saved = await saveGeneration(svc, generation.id);
    assert.ok(saved.savedAt);
    assert.equal(saved.expiresAt, null);
    const savedAgain = await saveGeneration(svc, generation.id);
    assert.equal(savedAgain.savedAt, saved.savedAt);
    const wavKey = generation.wavObjectKey!;
    const mp3Key = generation.mp3ObjectKey!;
    await deleteGeneration(svc, generation.id);
    assert.equal(svc.objectsMap.has(wavKey), false);
    assert.equal(svc.objectsMap.has(mp3Key), false);
    assert.equal(await svc.store.get(generation.id), null);
  });

  it("refuses to delete a tampered non-generate key", async () => {
    const store = memoryGenerationStore();
    const svc = testService({ store });
    await store.insert({
      id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
      createdAt: "2026-11-07T00:00:00.000Z",
      updatedAt: "2026-11-07T00:00:00.000Z",
      savedAt: null,
      expiresAt: "2026-11-08T00:00:00.000Z",
      status: "ready",
      error: null,
      title: "unsafe",
      kind: "tts",
      model: "gemini-3.8-flash-tts",
      requestId: null,
      contentHash: "x",
      lines: [{ id: "1", text: "a", voice: VOICE }],
      lineTimings: null,
      tokenSync: null,
      transcript: "a",
      wavObjectKey: "tts/voice-takes/secret.wav",
      mp3ObjectKey: null,
      obsoleteObjectKeys: [],
      sampleRate: RATE,
      durationSeconds: 1,
      byteCount: 10,
      revision: 0,
    });
    await assert.rejects(
      () => deleteGeneration(svc, "dddddddd-dddd-dddd-dddd-dddddddddddd"),
      /non-Generate/,
    );
  });
});

describe("getPlayableMp3", () => {
  it("returns MPEG bytes, not a renamed WAV", async () => {
    const svc = testService();
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    });
    const { mp3 } = await getPlayableMp3(svc, generation.id);
    assert.equal(isMpegAudio(mp3), true);
    assert.equal(mp3.toString("ascii", 0, 4) === "RIFF", false);
  });
});

describe("alignGeneration", () => {
  it("writes established tokenSync JSON and keeps generated line pauses", async () => {
    const svc = testService({
      tokenizer: {
        async tokenize(texts) {
          return texts.map((text) => ({
            text,
            tokens: [
              { text: text.slice(0, 1) || "あ" },
              { text: text.slice(1) || "い" },
            ],
          }));
        },
      },
    });
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      lines: [{ id: "1", text: "あい", voice: VOICE }],
    });
    const aligned = await alignGeneration(svc, generation.id, "あい");
    assert.equal(aligned.tokenSync?.version, 1);
    assert.ok(aligned.tokenSync?.lines[0].tokens[0].startSeconds != null);
    assert.equal(aligned.lineTimings?.[0].startSeconds, 0);
    assert.equal(aligned.lineTimings?.[0].endSeconds, 1);
  });

  it("fails clearly when the aligner is not configured", async () => {
    const svc = testService({
      aligner: {
        configured: () => false,
        async align() {
          throw new Error("should not run");
        },
      },
    });
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    });
    await assert.rejects(
      () => alignGeneration(svc, generation.id, "はい"),
      /ALIGNER_URL/,
    );
  });
});

describe("silence helper", () => {
  it("does not treat WAV as MP3", () => {
    const wav = pcm16ToWav(silencePcm16(RATE, 0.2), RATE);
    assert.equal(isMpegAudio(wav), false);
  });
});

describe("atomic reservation before TTS", () => {
  it("retries a failed request id without leaving the first objects", async () => {
    let n = 0;
    const svc = testService({
      tts: {
        sampleRate: RATE,
        async synthesizeLine() {
          n += 1;
          if (n === 1) throw new Error("Gemini request failed (HTTP 502): boom");
          return pcm(RATE);
        },
      },
    });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    await assert.rejects(() => createTtsGeneration(svc, input), /502/);
    const retry = await createTtsGeneration(svc, input);
    assert.equal(retry.reused, false);
    assert.equal(retry.generation.status, "ready");
    assert.equal(n, 2);
    assert.equal(svc.objectsMap.size, 2);
  });

  it("does not synthesize twice when a duplicate request arrives mid-flight", async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    let calls = 0;
    const svc = testService({
      tts: {
        sampleRate: RATE,
        async synthesizeLine() {
          calls += 1;
          await gate;
          return pcm(RATE);
        },
      },
    });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "ffffffff-ffff-ffff-ffff-ffffffffffff",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    const first = createTtsGeneration(svc, input);
    let pending = false;
    for (let i = 0; i < 50; i++) {
      const row = await svc.store.getByRequestId(input.requestId);
      if (row?.status === "pending") {
        pending = true;
        break;
      }
      await new Promise((resolve) => setImmediate(resolve));
    }
    assert.equal(pending, true);
    await assert.rejects(() => createTtsGeneration(svc, input), /already generating/);
    release();
    const result = await first;
    assert.equal(result.reused, false);
    assert.equal(calls, 1);
  });
});

describe("object cleanup", () => {
  it("rolls back a partial R2 put and does not leave a ready clip", async () => {
    const svc = testService();
    svc.objects.put = async (key, body) => {
      if (key.endsWith(".mp3")) throw new Error("R2 down");
      svc.objectsMap.set(key, Buffer.from(body));
    };
    await assert.rejects(
      () =>
        createTtsGeneration(svc, {
          model: "gemini-3.8-flash-tts",
          requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1",
          lines: [{ id: "1", text: "はい", voice: VOICE }],
        }),
      /R2 down/,
    );
    assert.equal(svc.objectsMap.size, 0);
    const listed = await listGenerations(svc);
    assert.equal(listed.generations.length, 0);
    const rows = await svc.store.list();
    assert.equal(rows[0]?.status, "failed");
  });

  it("treats a missing object as a successful delete", async () => {
    const svc = testService();
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    });
    svc.objects.delete = async () => {
      throw Object.assign(new Error("The specified key does not exist."), {
        name: "NoSuchKey",
        $metadata: { httpStatusCode: 404 },
      });
    };
    await deleteGeneration(svc, generation.id);
    assert.equal(await svc.store.get(generation.id), null);
  });

  it("does not delete metadata when R2 delete fails for a non-missing reason", async () => {
    const svc = testService();
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    });
    svc.objects.delete = async () => {
      throw Object.assign(new Error("AccessDenied"), { name: "AccessDenied" });
    };
    await assert.rejects(
      () => deleteGeneration(svc, generation.id),
      /clip was not removed/,
    );
    assert.ok(await svc.store.get(generation.id));
    assert.equal(svc.objectsMap.size, 2);
  });
});

describe("temporary lifetime cleanup", () => {
  it("deletes expired unsaved rows and their objects", async () => {
    let now = new Date("2026-11-07T00:00:00.000Z");
    const svc = testService({ now: () => now });
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    });
    assert.ok(generation.expiresAt);
    now = new Date("2026-11-08T00:00:01.000Z");
    const result = await cleanupExpiredGenerations(svc);
    assert.equal(result.deleted, 1);
    assert.equal(result.failed, 0);
    assert.equal(svc.objectsMap.size, 0);
    assert.equal(await svc.store.get(generation.id), null);
    assert.equal((await listGenerations(svc)).generations.length, 0);
  });

  it("does not expire a saved clip after the unsaved TTL", async () => {
    let now = new Date("2026-11-07T00:00:00.000Z");
    const svc = testService({ now: () => now });
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    });
    await saveGeneration(svc, generation.id);
    now = new Date("2026-11-10T00:00:00.000Z");
    const result = await cleanupExpiredGenerations(svc);
    assert.equal(result.deleted, 0);
    assert.ok(await svc.store.get(generation.id));
    assert.equal(svc.objectsMap.size, 2);
    assert.equal((await listGenerations(svc)).generations[0]?.saved, true);
  });

  it("does not call indefinite storage temporary in the lifetime copy", async () => {
    const listed = await listGenerations(testService());
    assert.match(listed.temporaryLifetime, /expire after 24 hours/);
    assert.match(listed.temporaryLifetime, /next daily cleanup/);
    assert.match(listed.temporaryLifetime, /48 hours after creation/);
    assert.doesNotMatch(listed.temporaryLifetime, /then deleted from Studio storage/);
    assert.doesNotMatch(listed.temporaryLifetime, /until you save them to the library or delete them/);
  });

  it("claims purging before deleting objects", async () => {
    let now = new Date("2026-11-07T00:00:00.000Z");
    const svc = testService({ now: () => now });
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa6",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    });
    now = new Date("2026-11-08T00:00:01.000Z");
    const innerDelete = svc.objects.delete.bind(svc.objects);
    svc.objects.delete = async (key) => {
      const row = await svc.store.get(generation.id);
      assert.equal(row?.status, "purging");
      await innerDelete(key);
    };
    const result = await cleanupExpiredGenerations(svc);
    assert.equal(result.deleted, 1);
    assert.equal(await svc.store.get(generation.id), null);
  });
});

function gateClaims(
  store: GenerationStore,
  type: GenerationClaim["type"],
): { ready: Promise<void> } {
  const inner = store.compareAndUpdate.bind(store);
  let waiters = 0;
  let release!: () => void;
  const ready = new Promise<void>((resolve) => {
    release = resolve;
  });
  store.compareAndUpdate = async (id, revision, claim, patch) => {
    if (claim.type === type) {
      waiters += 1;
      if (waiters >= 2) release();
      await ready;
    }
    return inner(id, revision, claim, patch);
  };
  return { ready };
}

describe("concurrent reclaim", () => {
  it("lets only one failed retry synthesize, and the loser cannot delete the winner output", async () => {
    let n = 0;
    const svc = testService({
      tts: {
        sampleRate: RATE,
        async synthesizeLine() {
          n += 1;
          if (n === 1) throw new Error("Gemini request failed (HTTP 502): boom");
          return pcm(RATE);
        },
      },
    });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa7",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    await assert.rejects(() => createTtsGeneration(svc, input), /502/);
    gateClaims(svc.store, "reclaim");
    const deleted: string[] = [];
    const innerDelete = svc.objects.delete.bind(svc.objects);
    svc.objects.delete = async (key) => {
      deleted.push(key);
      await innerDelete(key);
    };
    const results = await Promise.allSettled([
      createTtsGeneration(svc, input),
      createTtsGeneration(svc, input),
    ]);
    const fulfilled = results.filter(
      (result): result is PromiseFulfilledResult<{ generation: GenerationRecord; reused: boolean }> =>
        result.status === "fulfilled",
    );
    const rejected = results.filter((result) => result.status === "rejected");
    assert.equal(fulfilled.length, 1);
    assert.equal(rejected.length, 1);
    assert.match(String((rejected[0] as PromiseRejectedResult).reason), /already generating/);
    assert.equal(n, 2);
    const winner = fulfilled[0].value.generation;
    assert.equal(winner.status, "ready");
    assert.equal(svc.objectsMap.has(winner.wavObjectKey!), true);
    assert.equal(svc.objectsMap.has(winner.mp3ObjectKey!), true);
    const winnerKeys = new Set([winner.wavObjectKey!, winner.mp3ObjectKey!]);
    assert.equal(
      deleted.filter((key) => winnerKeys.has(key) && !svc.objectsMap.has(key)).length,
      0,
    );
  });

  it("lets only one stale pending retry synthesize", async () => {
    const requestId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa8";
    const started = new Date("2026-11-07T00:00:00.000Z");
    const later = new Date(started.getTime() + GENERATE_PENDING_STALE_MS + 1000);
    const store = memoryGenerationStore();
    await store.insert({
      id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa9",
      createdAt: started.toISOString(),
      updatedAt: started.toISOString(),
      savedAt: null,
      expiresAt: later.toISOString(),
      status: "pending",
      revision: 0,
      error: null,
      title: "stale",
      kind: "tts",
      model: "gemini-3.8-flash-tts",
      requestId,
      contentHash: "stale",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
      lineTimings: null,
      tokenSync: null,
      transcript: "はい",
      wavObjectKey: null,
      mp3ObjectKey: null,
      obsoleteObjectKeys: [],
      sampleRate: RATE,
      durationSeconds: 0,
      byteCount: null,
    });
    const svc = testService({ store, now: () => later });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId,
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    gateClaims(svc.store, "reclaim");
    const results = await Promise.allSettled([
      createTtsGeneration(svc, input),
      createTtsGeneration(svc, input),
    ]);
    const fulfilled = results.filter((result) => result.status === "fulfilled");
    assert.equal(fulfilled.length, 1);
    assert.equal(svc.synthCalls, 1);
    const winner = (fulfilled[0] as PromiseFulfilledResult<{ generation: GenerationRecord }>).value
      .generation;
    assert.equal(winner.status, "ready");
    assert.equal(svc.objectsMap.size, 2);
  });

  it("does not let a delayed failed-attempt R2 delete remove retry audio", async () => {
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa12",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    const svc = testService({
      randomId: () => "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa13",
    });
    const innerCas = svc.store.compareAndUpdate.bind(svc.store);
    let failReadyOnce = true;
    svc.store.compareAndUpdate = async (id, revision, claim, patch) => {
      if (failReadyOnce && claim.type === "pending" && patch.status === "ready") {
        failReadyOnce = false;
        throw new Error("finalize failed after upload");
      }
      return innerCas(id, revision, claim, patch);
    };

    let resumeDelete!: () => void;
    const deleteBlocked = new Promise<void>((resolve) => {
      resumeDelete = resolve;
    });
    let sawBlockedDelete!: () => void;
    const blocked = new Promise<void>((resolve) => {
      sawBlockedDelete = resolve;
    });
    let blockFirstDelete = true;
    const delayedDeletes: string[] = [];
    const innerDelete = svc.objects.delete.bind(svc.objects);
    svc.objects.delete = async (key) => {
      if (blockFirstDelete) {
        blockFirstDelete = false;
        sawBlockedDelete();
        await deleteBlocked;
        delayedDeletes.push(key);
      }
      await innerDelete(key);
    };

    const first = createTtsGeneration(svc, input);
    await blocked;
    const retry = await createTtsGeneration(svc, input);
    assert.equal(retry.reused, false);
    assert.equal(retry.generation.status, "ready");
    const wavKey = retry.generation.wavObjectKey!;
    const mp3Key = retry.generation.mp3ObjectKey!;
    assert.match(wavKey, /\/[1-9]\d*\/audio\.wav$/);
    assert.equal(mp3Key, wavKey.replace(/audio\.wav$/, "audio.mp3"));
    assert.notEqual(wavKey, generateWavKey(retry.generation.id, 0));
    assert.notEqual(mp3Key, generateMp3Key(retry.generation.id, 0));
    assert.equal(svc.objectsMap.has(wavKey), true);
    assert.equal(svc.objectsMap.has(mp3Key), true);

    resumeDelete();
    await assert.rejects(() => first, /finalize failed after upload/);
    assert.equal(svc.objectsMap.has(wavKey), true);
    assert.equal(svc.objectsMap.has(mp3Key), true);
    assert.equal(delayedDeletes.includes(wavKey), false);
    assert.equal(delayedDeletes.includes(mp3Key), false);
    const { mp3 } = await getPlayableMp3(svc, retry.generation.id);
    assert.equal(isMpegAudio(mp3), true);
    const ready = await svc.store.get(retry.generation.id);
    assert.equal(ready?.status, "ready");
    assert.equal(ready?.wavObjectKey, wavKey);
    assert.equal(svc.objectsMap.has(ready!.wavObjectKey!), true);
    assert.equal(svc.objectsMap.has(ready!.mp3ObjectKey!), true);
  });
});

describe("cleanup races save and retry", () => {
  it("keeps assets when a listed expiration candidate is saved before the purge claim", async () => {
    let now = new Date("2026-11-07T00:00:00.000Z");
    const svc = testService({ now: () => now });
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa10",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    });
    now = new Date("2026-11-08T00:00:01.000Z");
    const innerList = svc.store.listCleanupCandidates.bind(svc.store);
    svc.store.listCleanupCandidates = async (nowIso, staleBeforeIso, limit) => {
      const candidates = await innerList(nowIso, staleBeforeIso, limit);
      assert.equal(candidates.some((row) => row.id === generation.id), true);
      await saveGeneration(svc, generation.id);
      return candidates;
    };
    const result = await cleanupExpiredGenerations(svc);
    assert.equal(result.deleted, 0);
    const saved = await svc.store.get(generation.id);
    assert.ok(saved?.savedAt);
    assert.equal(saved?.status, "ready");
    assert.equal(svc.objectsMap.size, 2);
  });

  it("keeps winner assets when a listed expiration candidate is retried before the purge claim", async () => {
    let now = new Date("2026-11-07T00:00:00.000Z");
    const svc = testService({ now: () => now });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa11",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    const first = await createTtsGeneration(svc, input);
    now = new Date("2026-11-08T00:00:01.000Z");
    const innerList = svc.store.listCleanupCandidates.bind(svc.store);
    svc.store.listCleanupCandidates = async (nowIso, staleBeforeIso, limit) => {
      const candidates = await innerList(nowIso, staleBeforeIso, limit);
      assert.equal(candidates.some((row) => row.id === first.generation.id), true);
      const retry = await createTtsGeneration(svc, input);
      assert.equal(retry.reused, false);
      assert.equal(retry.generation.status, "ready");
      return candidates;
    };
    const result = await cleanupExpiredGenerations(svc);
    assert.equal(result.deleted, 0);
    const winner = await svc.store.get(first.generation.id);
    assert.equal(winner?.status, "ready");
    assert.ok(winner?.wavObjectKey);
    assert.equal(svc.objectsMap.has(winner!.wavObjectKey!), true);
    assert.equal(svc.objectsMap.has(winner!.mp3ObjectKey!), true);
  });
});

function denyObjectDeletes(svc: GenerateService & { objectsMap: Map<string, Buffer> }) {
  const inner = svc.objects.delete.bind(svc.objects);
  svc.objects.delete = async () => {
    throw Object.assign(new Error("AccessDenied"), { name: "AccessDenied" });
  };
  return () => {
    svc.objects.delete = inner;
  };
}

describe("obsolete object ledger", () => {
  /**
   * Rejected premise: a single mutable row's current keys are enough to track
   * every allocated object across retries/crashes.
   */
  it("keeps old attempt keys discoverable after reclaim CAS when old delete fails", async () => {
    let now = new Date("2026-11-07T00:00:00.000Z");
    const svc = testService({ now: () => now });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa14",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    const first = await createTtsGeneration(svc, input);
    const oldWav = first.generation.wavObjectKey!;
    const oldMp3 = first.generation.mp3ObjectKey!;
    now = new Date(now.getTime() + GENERATE_TEMPORARY_TTL_MS + 1000);
    const restore = denyObjectDeletes(svc);
    const retry = await createTtsGeneration(svc, input);
    restore();
    const row = await svc.store.get(first.generation.id);
    assert.equal(retry.generation.status, "ready");
    assert.notEqual(row?.wavObjectKey, oldWav);
    assert.notEqual(row?.mp3ObjectKey, oldMp3);
    assert.equal(row?.obsoleteObjectKeys.includes(oldWav), true);
    assert.equal(row?.obsoleteObjectKeys.includes(oldMp3), true);
    assert.equal(svc.objectsMap.has(oldWav), true);
    assert.equal(svc.objectsMap.has(oldMp3), true);
    assert.equal(svc.objectsMap.has(row!.wavObjectKey!), true);
    assert.equal(svc.objectsMap.has(row!.mp3ObjectKey!), true);
  });

  it("lets cron delete obsolete prefixes after rollover while keeping the winner", async () => {
    let now = new Date("2026-11-07T00:00:00.000Z");
    const svc = testService({ now: () => now });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa15",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    const first = await createTtsGeneration(svc, input);
    const oldWav = first.generation.wavObjectKey!;
    now = new Date(now.getTime() + GENERATE_TEMPORARY_TTL_MS + 1000);
    const restore = denyObjectDeletes(svc);
    const retry = await createTtsGeneration(svc, input);
    restore();
    assert.equal(svc.objectsMap.has(oldWav), true);
    const flushed = await cleanupExpiredGenerations(svc);
    assert.equal(flushed.deleted, 0);
    const row = await svc.store.get(first.generation.id);
    assert.equal(row?.status, "ready");
    assert.deepEqual(row?.obsoleteObjectKeys, []);
    assert.equal(svc.objectsMap.has(oldWav), false);
    assert.equal(svc.objectsMap.has(retry.generation.wavObjectKey!), true);
    assert.equal(svc.objectsMap.has(retry.generation.mp3ObjectKey!), true);
  });

  it("accumulates obsolete keys across repeated retries and then cron-cleans them", async () => {
    let now = new Date("2026-11-07T00:00:00.000Z");
    const svc = testService({ now: () => now });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa16",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    const first = await createTtsGeneration(svc, input);
    const attempt0 = [first.generation.wavObjectKey!, first.generation.mp3ObjectKey!];
    now = new Date(now.getTime() + GENERATE_TEMPORARY_TTL_MS + 1000);
    const restore = denyObjectDeletes(svc);
    const second = await createTtsGeneration(svc, input);
    const attempt1 = [second.generation.wavObjectKey!, second.generation.mp3ObjectKey!];
    now = new Date(now.getTime() + GENERATE_TEMPORARY_TTL_MS + 1000);
    const third = await createTtsGeneration(svc, input);
    restore();
    const row = await svc.store.get(first.generation.id);
    for (const key of [...attempt0, ...attempt1]) {
      assert.equal(row?.obsoleteObjectKeys.includes(key), true);
      assert.equal(svc.objectsMap.has(key), true);
    }
    assert.equal(svc.objectsMap.has(third.generation.wavObjectKey!), true);
    await cleanupExpiredGenerations(svc);
    const cleaned = await svc.store.get(first.generation.id);
    assert.deepEqual(cleaned?.obsoleteObjectKeys, []);
    assert.equal(cleaned?.wavObjectKey, third.generation.wavObjectKey);
    for (const key of [...attempt0, ...attempt1]) {
      assert.equal(svc.objectsMap.has(key), false);
    }
    assert.equal(svc.objectsMap.has(third.generation.wavObjectKey!), true);
    assert.equal(svc.objectsMap.has(third.generation.mp3ObjectKey!), true);
  });

  it("flushes obsolete keys of a saved clip without deleting the saved audio", async () => {
    let now = new Date("2026-11-07T00:00:00.000Z");
    const svc = testService({ now: () => now });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa17",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    const first = await createTtsGeneration(svc, input);
    const oldWav = first.generation.wavObjectKey!;
    now = new Date(now.getTime() + GENERATE_TEMPORARY_TTL_MS + 1000);
    const restore = denyObjectDeletes(svc);
    const retry = await createTtsGeneration(svc, input);
    restore();
    const saved = await saveGeneration(svc, retry.generation.id);
    assert.ok(saved.savedAt);
    now = new Date(now.getTime() + GENERATE_TEMPORARY_TTL_MS * 3);
    const result = await cleanupExpiredGenerations(svc);
    assert.equal(result.deleted, 0);
    const row = await svc.store.get(saved.id);
    assert.ok(row?.savedAt);
    assert.equal(row?.status, "ready");
    assert.deepEqual(row?.obsoleteObjectKeys, []);
    assert.equal(svc.objectsMap.has(oldWav), false);
    assert.equal(svc.objectsMap.has(row!.wavObjectKey!), true);
    assert.equal(svc.objectsMap.has(row!.mp3ObjectKey!), true);
  });

  it("does not let cron ledger flush steal a pending reservation revision during synthesis", async () => {
    let now = new Date("2026-11-07T00:00:00.000Z");
    let blockSynth = false;
    let releaseSynth!: () => void;
    const synthBlocked = new Promise<void>((resolve) => {
      releaseSynth = resolve;
    });
    let sawPendingSynth!: () => void;
    const pendingSynth = new Promise<void>((resolve) => {
      sawPendingSynth = resolve;
    });
    const svc = testService({
      now: () => now,
      tts: {
        sampleRate: RATE,
        async synthesizeLine() {
          if (blockSynth) {
            sawPendingSynth();
            await synthBlocked;
          }
          return pcm(RATE);
        },
      },
    });
    const input = {
      model: "gemini-3.8-flash-tts" as const,
      requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa18",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    };
    const first = await createTtsGeneration(svc, input);
    const oldWav = first.generation.wavObjectKey!;
    now = new Date(now.getTime() + GENERATE_TEMPORARY_TTL_MS + 1000);
    const restore = denyObjectDeletes(svc);
    blockSynth = true;
    const retry = createTtsGeneration(svc, input);
    await pendingSynth;
    const inflight = await svc.store.get(first.generation.id);
    assert.equal(inflight?.status, "pending");
    assert.equal(inflight?.obsoleteObjectKeys.includes(oldWav), true);
    const revisionBeforeCron = inflight!.revision;
    restore();
    await cleanupExpiredGenerations(svc);
    const duringSynth = await svc.store.get(first.generation.id);
    assert.equal(duringSynth?.status, "pending");
    assert.equal(duringSynth?.revision, revisionBeforeCron);
    releaseSynth();
    const result = await retry;
    assert.equal(result.reused, false);
    assert.equal(result.generation.status, "ready");
    assert.equal(svc.objectsMap.has(result.generation.wavObjectKey!), true);
    assert.equal(svc.objectsMap.has(result.generation.mp3ObjectKey!), true);
    await cleanupExpiredGenerations(svc);
    const ready = await svc.store.get(first.generation.id);
    assert.equal(ready?.status, "ready");
    assert.deepEqual(ready?.obsoleteObjectKeys, []);
    assert.equal(svc.objectsMap.has(oldWav), false);
    assert.equal(svc.objectsMap.has(ready!.wavObjectKey!), true);
  });
});



