import "server-only";
import { NextResponse } from "next/server";
import { isClipStepModel } from "@/lib/gemini/models";
import { ClipPipelineError } from "@/lib/experiments/clips/asr";
import { createHash, timingSafeEqual } from "node:crypto";
import { readClipDraft, isValidClipId, writeClipDraft } from "@/lib/experiments/clips/store";
import { fetchYouTubeVideoInfo } from "@/lib/experiments/clips/youtube-info";
import {
  CLIP_DEFAULT_SHIFT_SECONDS,
  type ClipDraft,
  type ClipOrientation,
  type ClipVideoInfo,
} from "@/lib/experiments/clips/types";

export function clipErrorResponse(error: unknown): NextResponse {
  if (error instanceof ClipPipelineError) {
    return NextResponse.json({ error: error.message }, { status: error.status });
  }
  console.error("[experiments/clips]", error);
  return NextResponse.json(
    { error: error instanceof Error ? error.message : "Unexpected error" },
    { status: 500 }
  );
}

/** Loads the draft or returns the 400/404 response to send. */
export async function loadClipOr404(
  id: string
): Promise<{ draft: ClipDraft } | { response: NextResponse }> {
  if (!isValidClipId(id)) {
    return { response: NextResponse.json({ error: "Invalid clip id" }, { status: 400 }) };
  }
  const draft = await readClipDraft(id);
  if (!draft) {
    return { response: NextResponse.json({ error: "Not found" }, { status: 404 }) };
  }
  return { draft };
}

/**
 * Optional `{ model }` in a step's JSON body (the editor's model picker).
 * Undefined means the server default; unknown ids are rejected.
 */
export async function requestedStepModel(request: Request): Promise<string | undefined> {
  const body = (await request.json().catch(() => null)) as { model?: unknown } | null;
  const model = body?.model;
  if (model === undefined || model === null || model === "") return undefined;
  if (!isClipStepModel(model)) {
    throw new ClipPipelineError(`Unsupported model “${String(model)}”.`, 400);
  }
  return model;
}

/** Duration of a PCM WAV from its header, or null if it isn't one we wrote. */
export function pcmWavInfo(
  wav: Buffer
): { sampleRate: number; channels: number; durationSec: number } | null {
  if (wav.length < 44) return null;
  if (wav.toString("ascii", 0, 4) !== "RIFF" || wav.toString("ascii", 8, 12) !== "WAVE") {
    return null;
  }
  const channels = wav.readUInt16LE(22);
  const sampleRate = wav.readUInt32LE(24);
  const byteRate = wav.readUInt32LE(28);
  if (sampleRate <= 0 || byteRate <= 0) return null;
  return { sampleRate, channels, durationSec: (wav.length - 44) / byteRate };
}

/**
 * Writes the first draft of a clip whose audio is already in R2. Also looks
 * up the video's title and channel (unless `video` is passed, e.g. looked up
 * once for a run of clips); best effort, since the editor's Refresh (or
 * "Process" on the list) can fill them in later.
 */
export async function createClipDraft(input: {
  id: string;
  videoId: string;
  startSec: number;
  endSec: number;
  orientation: ClipOrientation;
  /** Duration of the stored clip.wav. */
  durationSec: number;
  /** Already looked up (null = tried and failed); omitted = look it up now. */
  video?: ClipVideoInfo | null;
}): Promise<ClipDraft> {
  const video =
    input.video === undefined
      ? await fetchYouTubeVideoInfo(input.videoId).catch(() => undefined)
      : input.video;
  const now = new Date().toISOString();
  return writeClipDraft({
    id: input.id,
    videoId: input.videoId,
    ...(video ? { video } : {}),
    startSec: input.startSec,
    endSec: input.endSec,
    orientation: input.orientation,
    durationSec: Math.round(input.durationSec * 1000) / 1000,
    shiftSec: CLIP_DEFAULT_SHIFT_SECONDS,
    sentences: [],
    createdAt: now,
    updatedAt: now,
  });
}

/** What a pending clip stores in place of its upload ticket token. */
export function clipUploadTokenHash(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/** True when `Authorization: Bearer <token>` hashes to `tokenHash`. */
export function clipUploadTokenMatches(authorization: string | null, tokenHash: string): boolean {
  const token = /^Bearer\s+(\S+)$/i.exec(authorization ?? "")?.[1];
  if (!token) return false;
  const given = Buffer.from(clipUploadTokenHash(token), "hex");
  const expected = Buffer.from(tokenHash, "hex");
  return given.length === expected.length && timingSafeEqual(given, expected);
}
