import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { pcm16ToWav, wavToPcm16 } from "@/lib/tts/wav";
import { GEMINI_TTS_VOICES } from "@/lib/tts/gemini-voices";
import {
  alignGeneration,
  createTtsGeneration,
  deleteGeneration,
  getPlayableMp3,
  saveGeneration,
  type GenerateService,
} from "./service";
import { memoryGenerationStore } from "./store";
import { GENERATE_R2_PREFIX } from "./keys";
import { GenerateUserError } from "./validate";
import { isMpegAudio, silencePcm16 } from "./compose";

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

  it("surfaces a TTS failure without writing a row", async () => {
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
          lines: [{ id: "1", text: "はい", voice: VOICE }],
        }),
      /502/,
    );
    assert.deepEqual(await svc.store.list(), []);
    assert.equal(svc.objectsMap.size, 0);
  });

  it("rejects an unknown voice before calling TTS", async () => {
    const svc = testService();
    await assert.rejects(
      () =>
        createTtsGeneration(svc, {
          model: "gemini-3.8-flash-tts",
          lines: [{ id: "1", text: "はい", voice: "Nope" }],
        }),
      GenerateUserError,
    );
    assert.equal(svc.synthCalls, 0);
  });
});

describe("save and delete", () => {
  it("save is idempotent and delete only removes generate objects", async () => {
    const svc = testService();
    const { generation } = await createTtsGeneration(svc, {
      model: "gemini-3.8-flash-tts",
      lines: [{ id: "1", text: "はい", voice: VOICE }],
    });
    const saved = await saveGeneration(svc, generation.id);
    assert.ok(saved.savedAt);
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
      sampleRate: RATE,
      durationSeconds: 1,
      byteCount: 10,
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
