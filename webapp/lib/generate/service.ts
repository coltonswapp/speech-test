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
import { isMissingObjectError } from "./missing-object";
import { DuplicateGenerationRequestError, type GenerationStore } from "./store";
import { stampGenerateTokenSync } from "./timing";
import {
  GENERATE_PENDING_STALE_MS,
  GENERATE_TEMPORARY_LIFETIME,
  GENERATE_TEMPORARY_TTL_MS,
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
  "wavObjectKey" | "mp3ObjectKey" | "error"
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
    id: row.id,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    savedAt: row.savedAt,
    expiresAt: row.expiresAt,
    status: row.status,
    title: row.title,
    kind: row.kind,
    model: row.model,
    requestId: row.requestId,
    contentHash: row.contentHash,
    lines: row.lines,
    lineTimings: row.lineTimings,
    tokenSync: row.tokenSync,
    transcript: row.transcript,
    sampleRate: row.sampleRate,
    durationSeconds: row.durationSeconds,
    byteCount: row.byteCount,
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

function addMs(date: Date, ms: number): Date {
  return new Date(date.getTime() + ms);
}

function isDuplicateRequestId(error: unknown): boolean {
  if (error instanceof DuplicateGenerationRequestError) return true;
  const e = error as { code?: string; constraint?: string; message?: string };
  if (e.code !== "23505") return false;
  return /request_id/i.test(String(e.constraint ?? e.message ?? ""));
}

function isExpiredUnsaved(row: GenerationRecord, now: Date): boolean {
  if (row.savedAt) return false;
  if (!row.expiresAt) return false;
  return Date.parse(row.expiresAt) <= now.getTime();
}

function isStalePending(row: GenerationRecord, now: Date): boolean {
  if (row.status !== "pending") return false;
  return now.getTime() - Date.parse(row.updatedAt) >= GENERATE_PENDING_STALE_MS;
}

function requireRequestId(requestId: string | undefined): string {
  if (!requestId) {
    throw new GenerateUserError("Missing request id.", 400);
  }
  return requestId;
}

function objectKeysFor(row: Pick<GenerationRecord, "id" | "wavObjectKey" | "mp3ObjectKey">): string[] {
  return [
    ...new Set(
      [row.wavObjectKey, row.mp3ObjectKey, generateWavKey(row.id), generateMp3Key(row.id)].filter(
        (key): key is string => Boolean(key),
      ),
    ),
  ];
}

async function deleteGenerateObject(objects: GenerateObjectStore, key: string) {
  if (!isGenerateObjectKey(key)) {
    throw new GenerateUserError("Refusing to delete a non-Generate object.", 500);
  }
  try {
    await objects.delete(key);
  } catch (error) {
    if (isMissingObjectError(error)) return;
    throw error;
  }
}

/**
 * Deletes generate objects. Missing keys are success. Any other R2 error
 * propagates so metadata is not removed while objects may still exist.
 */
export async function deleteTrackedGenerateObjects(
  objects: GenerateObjectStore,
  row: Pick<GenerationRecord, "id" | "wavObjectKey" | "mp3ObjectKey">,
): Promise<void> {
  for (const key of objectKeysFor(row)) {
    await deleteGenerateObject(objects, key);
  }
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

async function putPlayableAudio(
  svc: GenerateService,
  id: string,
  wav: Buffer,
  mp3: Buffer,
): Promise<{ wavObjectKey: string; mp3ObjectKey: string }> {
  const wavObjectKey = generateWavKey(id);
  const mp3ObjectKey = generateMp3Key(id);
  try {
    await putGenerateObject(svc.objects, wavObjectKey, wav, "audio/wav");
    await putGenerateObject(svc.objects, mp3ObjectKey, mp3, "audio/mpeg");
    return { wavObjectKey, mp3ObjectKey };
  } catch (error) {
    try {
      await deleteTrackedGenerateObjects(svc.objects, {
        id,
        wavObjectKey,
        mp3ObjectKey,
      });
    } catch {
      // Keep the original put error; cleanup cron will retry leftover keys.
    }
    throw error;
  }
}

function pendingRow(params: {
  id: string;
  now: Date;
  title: string;
  kind: GenerationRecord["kind"];
  model: string | null;
  requestId: string;
  contentHash: string;
  lines: GenerateLineInput[];
  transcript: string;
  sampleRate: number | null;
}): GenerationRecord {
  return {
    id: params.id,
    createdAt: iso(params.now),
    updatedAt: iso(params.now),
    savedAt: null,
    expiresAt: iso(addMs(params.now, GENERATE_PENDING_STALE_MS)),
    status: "pending",
    error: null,
    title: params.title,
    kind: params.kind,
    model: params.model,
    requestId: params.requestId,
    contentHash: params.contentHash,
    lines: params.lines,
    lineTimings: null,
    tokenSync: null,
    transcript: params.transcript,
    wavObjectKey: null,
    mp3ObjectKey: null,
    sampleRate: params.sampleRate,
    durationSeconds: 0,
    byteCount: null,
  };
}

async function markFailed(svc: GenerateService, row: GenerationRecord, error: unknown) {
  const now = svc.now?.() ?? new Date();
  const message = error instanceof Error ? error.message : "Generation failed.";
  try {
    await deleteTrackedGenerateObjects(svc.objects, row);
  } catch {
    // Keep the failed row so cleanup can retry object deletion.
  }
  await svc.store.update(row.id, {
    status: "failed",
    error: message.slice(0, 1000),
    wavObjectKey: null,
    mp3ObjectKey: null,
    expiresAt: iso(addMs(now, GENERATE_TEMPORARY_TTL_MS)),
    updatedAt: iso(now),
  });
}

async function reclaimReservation(
  svc: GenerateService,
  existing: GenerationRecord,
  now: Date,
): Promise<GenerationRecord> {
  try {
    await deleteTrackedGenerateObjects(svc.objects, existing);
  } catch (error) {
    throw new GenerateUserError(
      error instanceof Error
        ? `Could not clear previous audio before retry: ${error.message}`
        : "Could not clear previous audio before retry.",
      502,
    );
  }
  const updated = await svc.store.update(existing.id, {
    status: "pending",
    error: null,
    wavObjectKey: null,
    mp3ObjectKey: null,
    lineTimings: null,
    tokenSync: null,
    durationSeconds: 0,
    byteCount: null,
    expiresAt: iso(addMs(now, GENERATE_PENDING_STALE_MS)),
    updatedAt: iso(now),
  });
  if (!updated) throw new GenerateUserError("Not found.", 404);
  return updated;
}

/**
 * If this request id already has a ready clip, reuse it (no TTS).
 * In-flight pending reservations 409 so a second caller cannot charge twice.
 * Failed or stale pending rows are reclaimed for a genuine retry.
 */
async function resolveReservation(
  svc: GenerateService,
  existing: GenerationRecord,
  now: Date,
): Promise<{ generation: GenerationRecord; reused: true } | { reservation: GenerationRecord }> {
  if (existing.status === "ready" && !isExpiredUnsaved(existing, now)) {
    return { generation: existing, reused: true };
  }
  if (existing.status === "pending" && !isStalePending(existing, now)) {
    throw new GenerateUserError("This request is already generating.", 409);
  }
  return { reservation: await reclaimReservation(svc, existing, now) };
}

async function reserveRequest(
  svc: GenerateService,
  draft: GenerationRecord,
  now: Date,
): Promise<{ generation: GenerationRecord; reused: true } | { reservation: GenerationRecord }> {
  const requestId = draft.requestId;
  if (!requestId) throw new GenerateUserError("Missing request id.", 400);

  const existing = await svc.store.getByRequestId(requestId);
  if (existing) return resolveReservation(svc, existing, now);

  try {
    return { reservation: await svc.store.insert(draft) };
  } catch (error) {
    if (!isDuplicateRequestId(error)) throw error;
    const raced = await svc.store.getByRequestId(requestId);
    if (!raced) throw error;
    return resolveReservation(svc, raced, now);
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
  const requestId = requireRequestId(input.requestId);
  const lines = validateGenerateLines(input.lines, input.model);
  const contentHash = generationContentHash({
    kind: "tts",
    model: input.model,
    lines,
  });
  const draft = pendingRow({
    id: svc.randomId?.() ?? crypto.randomUUID(),
    now,
    title: input.title?.trim() || defaultTitleFromLines(lines),
    kind: "tts",
    model: input.model,
    requestId,
    contentHash,
    lines,
    transcript: transcriptFromLines(lines),
    sampleRate: svc.tts.sampleRate,
  });

  const reserved = await reserveRequest(svc, draft, now);
  if ("reused" in reserved) return reserved;

  const row = reserved.reservation;
  try {
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

    const keys = await putPlayableAudio(svc, row.id, wav, mp3);
    const readyAt = svc.now?.() ?? new Date();
    const updated = await svc.store.update(row.id, {
      status: "ready",
      error: null,
      title: draft.title,
      lines,
      contentHash,
      transcript: draft.transcript,
      lineTimings: composed.lineTimings,
      wavObjectKey: keys.wavObjectKey,
      mp3ObjectKey: keys.mp3ObjectKey,
      sampleRate: svc.tts.sampleRate,
      durationSeconds: composed.durationSeconds,
      byteCount: mp3.length,
      expiresAt: iso(addMs(readyAt, GENERATE_TEMPORARY_TTL_MS)),
      updatedAt: iso(readyAt),
    });
    if (!updated) throw new GenerateUserError("Not found.", 404);
    return { generation: updated, reused: false };
  } catch (error) {
    await markFailed(svc, row, error);
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
  const requestId = requireRequestId(input.requestId);
  const linesText = splitTranscript(input.transcript);
  if (linesText.length === 0) {
    throw new GenerateUserError("Paste a transcript to align.");
  }
  const lines: GenerateLineInput[] = linesText.map((text, index) => ({
    id: `upload-${index + 1}`,
    text,
    voice: "upload",
  }));
  const contentHash = generationContentHash({
    kind: "upload",
    lines,
    transcript: input.transcript,
  });
  const draft = pendingRow({
    id: svc.randomId?.() ?? crypto.randomUUID(),
    now,
    title: input.title?.trim() || defaultTitleFromLines(lines),
    kind: "upload",
    model: null,
    requestId,
    contentHash,
    lines,
    transcript: linesText.join("\n"),
    sampleRate: input.sampleRate ?? null,
  });

  const reserved = await reserveRequest(svc, draft, now);
  if ("reused" in reserved) return reserved.generation;

  const row = reserved.reservation;
  try {
    const wav = await svc.encoder.transcodeToWavMono(input.audio);
    const { pcm, sampleRate } = wavToPcm16(wav);
    const mp3 = await svc.encoder.encodeWavToMp3(wav);
    if (!isMpegAudio(mp3)) {
      throw new GenerateUserError(
        "MP3 encoding failed — the uploaded audio could not be encoded.",
        500,
      );
    }
    const keys = await putPlayableAudio(svc, row.id, wav, mp3);
    const readyAt = svc.now?.() ?? new Date();
    const durationSeconds = Math.floor(pcm.length / 2) / sampleRate;
    const updated = await svc.store.update(row.id, {
      status: "ready",
      error: null,
      wavObjectKey: keys.wavObjectKey,
      mp3ObjectKey: keys.mp3ObjectKey,
      sampleRate,
      durationSeconds,
      byteCount: mp3.length,
      expiresAt: iso(addMs(readyAt, GENERATE_TEMPORARY_TTL_MS)),
      updatedAt: iso(readyAt),
    });
    if (!updated) throw new GenerateUserError("Not found.", 404);
    return updated;
  } catch (error) {
    await markFailed(svc, row, error);
    throw error;
  }
}

export async function saveGeneration(
  svc: GenerateService,
  id: string,
): Promise<GenerationRecord> {
  const row = await requireReadyGeneration(svc, id);
  if (row.savedAt) return row;
  const now = iso(svc.now?.() ?? new Date());
  const updated = await svc.store.update(id, {
    savedAt: now,
    expiresAt: null,
    updatedAt: now,
  });
  if (!updated) throw new GenerateUserError("Not found.", 404);
  return updated;
}

export async function renameGeneration(
  svc: GenerateService,
  id: string,
  title: string,
): Promise<GenerationRecord> {
  await requireReadyGeneration(svc, id);
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
  try {
    await deleteTrackedGenerateObjects(svc.objects, row);
  } catch (error) {
    throw new GenerateUserError(
      error instanceof Error
        ? `Could not delete stored audio. The clip was not removed. ${error.message}`
        : "Could not delete stored audio. The clip was not removed.",
      502,
    );
  }
  await svc.store.delete(id);
}

export async function cleanupExpiredGenerations(
  svc: GenerateService,
  options: { limit?: number } = {},
): Promise<{ deleted: number; failed: number }> {
  const now = svc.now?.() ?? new Date();
  const candidates = await svc.store.listCleanupCandidates(iso(now), options.limit ?? 100);
  let deleted = 0;
  let failed = 0;
  for (const row of candidates) {
    if (row.savedAt) continue;
    try {
      await deleteTrackedGenerateObjects(svc.objects, row);
      await svc.store.delete(row.id);
      deleted += 1;
    } catch {
      failed += 1;
    }
  }
  return { deleted, failed };
}

export async function getPlayableMp3(
  svc: GenerateService,
  id: string,
): Promise<{ mp3: Buffer; title: string }> {
  const row = await requireReadyGeneration(svc, id);
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
  const row = await requireReadyGeneration(svc, id);
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

export async function requireReadyGeneration(
  svc: GenerateService,
  id: string,
): Promise<GenerationRecord> {
  const row = await requireGeneration(svc, id);
  const now = svc.now?.() ?? new Date();
  if (isExpiredUnsaved(row, now)) {
    throw new GenerateUserError("This unsaved clip has expired.", 410);
  }
  if (row.status !== "ready") {
    throw new GenerateUserError("This clip is not ready yet.", 409);
  }
  return row;
}

export async function listGenerations(svc: GenerateService): Promise<{
  generations: GenerationPublic[];
  temporaryLifetime: string;
}> {
  try {
    await cleanupExpiredGenerations(svc, { limit: 25 });
  } catch {
    // Listing still works; the cron retries leftover cleanup.
  }
  const now = svc.now?.() ?? new Date();
  const rows = await svc.store.list();
  return {
    generations: rows
      .filter((row) => row.status === "ready" && !isExpiredUnsaved(row, now))
      .map(publicGeneration),
    temporaryLifetime: GENERATE_TEMPORARY_LIFETIME,
  };
}

export function timingDownloadPayload(row: GenerationRecord): VariantTokenSync {
  if (!row.tokenSync) {
    throw new GenerateUserError("This clip has no timing yet.", 404);
  }
  return row.tokenSync;
}
