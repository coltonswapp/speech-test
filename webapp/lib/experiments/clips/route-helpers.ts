import "server-only";
import { NextResponse } from "next/server";
import { isClipStepModel } from "@/lib/gemini/models";
import { ClipPipelineError } from "@/lib/experiments/clips/asr";
import { readClipDraft, isValidClipId } from "@/lib/experiments/clips/store";
import type { ClipDraft } from "@/lib/experiments/clips/types";

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
export function pcmWavInfo(wav: Buffer): { sampleRate: number; durationSec: number } | null {
  if (wav.length < 44) return null;
  if (wav.toString("ascii", 0, 4) !== "RIFF" || wav.toString("ascii", 8, 12) !== "WAVE") {
    return null;
  }
  const sampleRate = wav.readUInt32LE(24);
  const byteRate = wav.readUInt32LE(28);
  if (sampleRate <= 0 || byteRate <= 0) return null;
  return { sampleRate, durationSec: (wav.length - 44) / byteRate };
}
