import { pcm16ToFloat32, pcm16ToWav, wavToPcm16 } from "@/lib/tts/wav";
import type { AlignerLineInput, AlignerResponse } from "@/lib/aligner/client";
import type { VariantTokenSync } from "@/lib/dialogue/types";
import {
  composeLinePcm,
  defaultTitleFromLines,
  generationContentHash,
  isMpegAudio,
  splitTranscript,
  transcriptFromLines,
  type LineClip,
} from "./compose";
import {
  assertGenerateObjectKey,
  generateMp3Key,
  generateWavKey,
  isGenerateObjectKey,
} from "./keys";
import { stampGenerateTokenSync } from "./timing";
import type { GenerationStore } from "./store";
import {
  GENERATE_TEMPORARY_LIFETIME,
  type GenerateLineInput,
  type GenerateLineTiming,
  type GenerationRecord,
} from "./types";
import { GenerateUserError, validateGenerateLines } from "./validate";

export type GenerateObjectStore = {
  put(key: string, body: Buffer, contentType: string): Promise<void>;
  get(key: string): Promise<Buffer>;
  delete(key: string): Promise<void>;
};

export type GenerateTts = {
  synthesizeLine(params: {
    text: string;
    voice: string;
    delivery?: string;
    model: string;
  }): Promise<Buffer>;
  sampleRate: number;
};

export type GenerateEncoder = {
  encodeWavToMp3(wav: Buffer): Promise<Buffer>;
  transcodeToWavMono(audio: Buffer, sampleRate?: number): Promise<Buffer>;
};

export type GenerateAligner = {
  configured(): boolean;
  align(params: {
    audioObjectKey: string;
    lines: AlignerLineInput[];
  }): Promise<AlignerResponse>;
};

export type GenerateTokenizer = {
  tokenize(
    texts: string[],
  ): Promise<Array<{ text: string; tokens: Array<{ text: string; reading?: string }> }>>;
};

export type GenerateService = {
  store: GenerationStore;
  objects: GenerateObjectStore;
  tts: GenerateTts;
  encoder: GenerateEncoder;
  aligner: GenerateAligner;
  tokenizer: GenerateTokenizer;
  now?: () => Date;
  randomId?: () => string;
};

export type GenerationPublic = Omit<
  GenerationRecord,
  "wavObjectKey" | "mp3ObjectKey"
> & {
  saved: boolean;
  audioUrl: string;
  downloadUrl: string;
  timingUrl: string | null;
  temporary: boolean;
};

export function publicGeneration(row: GenerationRecord): GenerationPublic {
  const saved = row.savedAt != null;
  return {
    ...row,
    saved,
    temporary: !saved,
    audioUrl: `/api/generate/${row.id}/audio`,
    downloadUrl: `/api/generate/${row.id}/audio?download=1`,
    timingUrl: row.tokenSync ? `/api/generate/${row.id}/timing` : null,
  };
}

function iso(date: Date): string {
  return date.toISOString();
}

async function putGenerateObject(
  objects: GenerateObjectStore,
  key: string,
  body: Buffer,
  contentType: string,
) {
  assertGenerateObjectKey(key);
  await objects.put(key, body, contentType);
}

async function deleteGenerateObject(objects: GenerateObjectStore, key: string | null) {
  if (!key) return;
  if (!isGenerateObjectKey(key)) {
    throw new GenerateUserError("Refusing to delete a non-Generate object.", 500);
  }
  try {
    await objects.delete(key);
  } catch {
    // Missing object should not block deleting the metadata row.
  }
}

export async function createTtsGeneration(
  svc: GenerateService,
  input: {
    title?: string;
    lines: GenerateLineInput[];
    requestId?: string;
    model: string;
  },
): Promise<{ generation: GenerationRecord; reused: boolean }> {
  const now = svc.now?.() ?? new Date();
  if (input.requestId) {
    const existing = await svc.store.getByRequestId(input.requestId);
    if (existing) return { generation: existing, reused: true };
  }

  const lines = validateGenerateLines(input.lines, input.model);
  const contentHash = generationContentHash({
    kind: "tts",
    model: input.model,
    lines,
  });

  const clips: LineClip[] = [];
  for (const line of lines) {
    const pcm = await svc.tts.synthesizeLine({
      text: line.text,
      voice: line.voice,
      delivery: line.delivery,
      model: input.model,
    });
    clips.push({ line, pcm });
  }

  const composed = composeLinePcm(clips, svc.tts.sampleRate);
  const wav = pcm16ToWav(composed.pcm, svc.tts.sampleRate);
  const mp3 = await svc.encoder.encodeWavToMp3(wav);
  if (!isMpegAudio(mp3)) {
    throw new GenerateUserError(
      "MP3 encoding failed — the combined file was not MPEG audio.",
      500,
    );
  }

  const id = svc.randomId?.() ?? crypto.randomUUID();
  const wavObjectKey = generateWavKey(id);
  const mp3ObjectKey = generateMp3Key(id);
  await putGenerateObject(svc.objects, wavObjectKey, wav, "audio/wav");
  await putGenerateObject(svc.objects, mp3ObjectKey, mp3, "audio/mpeg");

  const row: GenerationRecord = {
    id,
    createdAt: iso(now),
    updatedAt: iso(now),
    savedAt: null,
    title: input.title?.trim() || defaultTitleFromLines(lines),
    kind: "tts",
    model: input.model,
    requestId: input.requestId ?? null,
    contentHash,
    lines,
    lineTimings: composed.lineTimings,
    tokenSync: null,
    transcript: transcriptFromLines(lines),
    wavObjectKey,
    mp3ObjectKey,
    sampleRate: svc.tts.sampleRate,
    durationSeconds: composed.durationSeconds,
    byteCount: mp3.length,
  };
  try {
    return { generation: await svc.store.insert(row), reused: false };
  } catch (error) {
    if (input.requestId) {
      const existing = await svc.store.getByRequestId(input.requestId);
      if (existing) return { generation: existing, reused: true };
    }
    throw error;
  }
}

export async function createUploadGeneration(
  svc: GenerateService,
  input: {
    title?: string;
    transcript: string;
    audio: Buffer;
    durationSeconds: number;
    sampleRate?: number | null;
    requestId?: string;
  },
): Promise<GenerationRecord> {
  const now = svc.now?.() ?? new Date();
  if (input.requestId) {
    const existing = await svc.store.getByRequestId(input.requestId);
    if (existing) return existing;
  }
  const linesText = splitTranscript(input.transcript);
  if (linesText.length === 0) {
    throw new GenerateUserError("Paste a transcript to align.");
  }
  const wav = await svc.encoder.transcodeToWavMono(input.audio);
  const { pcm, sampleRate } = wavToPcm16(wav);
  const mp3 = await svc.encoder.encodeWavToMp3(wav);
  if (!isMpegAudio(mp3)) {
    throw new GenerateUserError(
      "MP3 encoding failed — the uploaded audio could not be encoded.",
      500,
    );
  }
  const durationSeconds = Math.floor(pcm.length / 2) / sampleRate;
  const lines: GenerateLineInput[] = linesText.map((text, index) => ({
    id: `upload-${index + 1}`,
    text,
    voice: "upload",
  }));
  const id = svc.randomId?.() ?? crypto.randomUUID();
  const wavObjectKey = generateWavKey(id);
  const mp3ObjectKey = generateMp3Key(id);
  await putGenerateObject(svc.objects, wavObjectKey, wav, "audio/wav");
  await putGenerateObject(svc.objects, mp3ObjectKey, mp3, "audio/mpeg");
  const row: GenerationRecord = {
    id,
    createdAt: iso(now),
    updatedAt: iso(now),
    savedAt: null,
    title: input.title?.trim() || defaultTitleFromLines(lines),
    kind: "upload",
    model: null,
    requestId: input.requestId ?? null,
    contentHash: generationContentHash({
      kind: "upload",
      lines,
      transcript: input.transcript,
    }),
    lines,
    lineTimings: null,
    tokenSync: null,
    transcript: linesText.join("\n"),
    wavObjectKey,
    mp3ObjectKey,
    sampleRate,
    durationSeconds,
    byteCount: mp3.length,
  };
  return svc.store.insert(row);
}

export async function saveGeneration(
  svc: GenerateService,
  id: string,
): Promise<GenerationRecord> {
  const row = await requireGeneration(svc, id);
  if (row.savedAt) return row;
  const now = iso(svc.now?.() ?? new Date());
  const updated = await svc.store.update(id, { savedAt: now, updatedAt: now });
  if (!updated) throw new GenerateUserError("Not found.", 404);
  return updated;
}

export async function renameGeneration(
  svc: GenerateService,
  id: string,
  title: string,
): Promise<GenerationRecord> {
  await requireGeneration(svc, id);
  const now = iso(svc.now?.() ?? new Date());
  const updated = await svc.store.update(id, { title: title.trim(), updatedAt: now });
  if (!updated) throw new GenerateUserError("Not found.", 404);
  return updated;
}

export async function deleteGeneration(
  svc: GenerateService,
  id: string,
): Promise<void> {
  const row = await requireGeneration(svc, id);
  await deleteGenerateObject(svc.objects, row.wavObjectKey);
  await deleteGenerateObject(svc.objects, row.mp3ObjectKey);
  await svc.store.delete(id);
}

export async function getPlayableMp3(
  svc: GenerateService,
  id: string,
): Promise<{ mp3: Buffer; title: string }> {
  const row = await requireGeneration(svc, id);
  if (!row.mp3ObjectKey) {
    throw new GenerateUserError("This clip has no MP3 yet.", 404);
  }
  assertGenerateObjectKey(row.mp3ObjectKey);
  const mp3 = await svc.objects.get(row.mp3ObjectKey);
  if (!isMpegAudio(mp3)) {
    throw new GenerateUserError("Stored audio is not a valid MP3.", 500);
  }
  return { mp3, title: row.title };
}

export async function alignGeneration(
  svc: GenerateService,
  id: string,
  transcript?: string,
): Promise<GenerationRecord> {
  const row = await requireGeneration(svc, id);
  if (!svc.aligner.configured()) {
    throw new GenerateUserError(
      "Alignment is not configured in this environment (ALIGNER_URL).",
      503,
    );
  }
  if (!row.wavObjectKey) {
    throw new GenerateUserError("This clip has no audio to align.", 400);
  }
  assertGenerateObjectKey(row.wavObjectKey);

  const text = (transcript ?? row.transcript ?? transcriptFromLines(row.lines)).trim();
  const lineTexts = splitTranscript(text);
  if (lineTexts.length === 0) {
    throw new GenerateUserError("Paste a transcript to align.");
  }

  let tokenized: Array<{
    text: string;
    tokens: Array<{ text: string; reading?: string }>;
  }>;
  try {
    tokenized = await svc.tokenizer.tokenize(lineTexts);
  } catch (error) {
    throw new GenerateUserError(
      error instanceof Error ? error.message : "Could not tokenize the transcript.",
      400,
    );
  }

  let aligned: AlignerResponse;
  try {
    aligned = await svc.aligner.align({
      audioObjectKey: row.wavObjectKey,
      lines: tokenized,
    });
  } catch (error) {
    throw new GenerateUserError(
      error instanceof Error ? error.message : "Alignment failed.",
      502,
    );
  }

  const wav = await svc.objects.get(row.wavObjectKey);
  const { pcm, sampleRate } = wavToPcm16(wav);
  const markSamples =
    row.kind === "tts" &&
    row.lineTimings &&
    row.lineTimings.length === tokenized.length
      ? row.lineTimings.slice(1).map((timing) =>
          Math.round(timing.startSeconds * sampleRate),
        )
      : null;

  const stamped = stampGenerateTokenSync({
    aligned: aligned.lines,
    lines: tokenized,
    samples: pcm16ToFloat32(pcm),
    sampleRate,
    contentHash: row.contentHash ?? generationContentHash({
      kind: row.kind,
      model: row.model,
      lines: row.lines,
      transcript: text,
    }),
    alignerVersion: aligned.alignerVersion,
    markSamples,
  });

  const now = iso(svc.now?.() ?? new Date());
  const lineTimings: GenerateLineTiming[] =
    row.kind === "tts" &&
    row.lineTimings &&
    row.lineTimings.length === tokenized.length
      ? row.lineTimings
      : stamped.lineTimings;

  const updated = await svc.store.update(id, {
    tokenSync: stamped.tokenSync,
    lineTimings,
    transcript: lineTexts.join("\n"),
    updatedAt: now,
  });
  if (!updated) throw new GenerateUserError("Not found.", 404);
  return updated;
}

export async function requireGeneration(
  svc: GenerateService,
  id: string,
): Promise<GenerationRecord> {
  const row = await svc.store.get(id);
  if (!row) throw new GenerateUserError("Not found.", 404);
  return row;
}

export async function listGenerations(svc: GenerateService): Promise<{
  generations: GenerationPublic[];
  temporaryLifetime: string;
}> {
  const rows = await svc.store.list();
  return {
    generations: rows.map(publicGeneration),
    temporaryLifetime: GENERATE_TEMPORARY_LIFETIME,
  };
}

export function timingDownloadPayload(row: GenerationRecord): VariantTokenSync {
  if (!row.tokenSync) {
    throw new GenerateUserError("This clip has no timing yet.", 404);
  }
  return row.tokenSync;
}
