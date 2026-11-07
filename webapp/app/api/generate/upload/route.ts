import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { probeAudioFile } from "@/lib/tts/audio-encode";
import {
  createUploadGeneration,
  publicGeneration,
} from "@/lib/generate/service";
import {
  GENERATE_UPLOAD_EXT,
  GENERATE_UPLOAD_MAX_BYTES,
  GENERATE_UPLOAD_MAX_SECONDS,
  GENERATE_UPLOAD_MIN_SECONDS,
  GENERATE_UPLOAD_TYPES,
} from "@/lib/generate/types";
import { studioGenerateService } from "@/lib/generate/runtime";
import { generateErrorResponse, requireGenerateAccess } from "@/lib/generate/http";
import { GenerateUserError } from "@/lib/generate/validate";

export const maxDuration = 300;

export async function POST(request: NextRequest) {
  const denied = await requireGenerateAccess(request);
  if (denied) return denied;

  const declared = Number(request.headers.get("content-length") ?? 0);
  if (declared > GENERATE_UPLOAD_MAX_BYTES) {
    return NextResponse.json(
      { error: "Audio must be 20 MB or smaller." },
      { status: 413 },
    );
  }

  let formData: FormData;
  try {
    formData = await request.formData();
  } catch {
    return NextResponse.json(
      { error: "Expected multipart form data with a file." },
      { status: 400 },
    );
  }

  if (formData.get("audioUrl") || formData.get("url")) {
    return NextResponse.json(
      { error: "Upload a file from this device. Remote URLs are not fetched." },
      { status: 400 },
    );
  }

  const file = formData.get("file");
  const transcript = String(formData.get("transcript") ?? "").trim();
  const title = String(formData.get("title") ?? "").trim();
  const requestIdRaw = String(formData.get("requestId") ?? "").trim();
  if (!/^[0-9a-f-]{36}$/i.test(requestIdRaw)) {
    return NextResponse.json({ error: "Missing request id." }, { status: 400 });
  }
  const requestId = requestIdRaw;

  if (!(file instanceof File)) {
    return NextResponse.json(
      { error: "Expected multipart field “file”." },
      { status: 400 },
    );
  }
  if (file.size > GENERATE_UPLOAD_MAX_BYTES) {
    return NextResponse.json(
      { error: "Audio must be 20 MB or smaller." },
      { status: 413 },
    );
  }
  if (!transcript) {
    return NextResponse.json(
      { error: "Paste a transcript to align." },
      { status: 400 },
    );
  }

  const contentType = (file.type || "").toLowerCase();
  const nameExt = file.name.split(".").pop()?.toLowerCase() ?? "";
  const ext =
    GENERATE_UPLOAD_TYPES.get(contentType) ?? GENERATE_UPLOAD_EXT[nameExt] ?? null;
  if (!ext) {
    return NextResponse.json(
      { error: "Use a WAV, MP3, M4A, OGG, or FLAC file." },
      { status: 400 },
    );
  }

  const bytes = Buffer.from(await file.arrayBuffer());
  let meta;
  try {
    meta = await probeAudioFile(bytes);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Could not read that audio file.";
    return NextResponse.json({ error: message }, { status: 400 });
  }
  if (meta.durationSeconds < GENERATE_UPLOAD_MIN_SECONDS) {
    return NextResponse.json(
      { error: "Audio is too short to align." },
      { status: 400 },
    );
  }
  if (meta.durationSeconds > GENERATE_UPLOAD_MAX_SECONDS) {
    return NextResponse.json(
      { error: "Audio must be 3 minutes or shorter." },
      { status: 400 },
    );
  }

  try {
    const row = await createUploadGeneration(studioGenerateService(), {
      title: title || undefined,
      transcript,
      audio: bytes,
      durationSeconds: meta.durationSeconds,
      sampleRate: meta.sampleRate,
      requestId,
    });
    return NextResponse.json({ generation: publicGeneration(row) });
  } catch (error) {
    if (error instanceof GenerateUserError) {
      return generateErrorResponse(error);
    }
    return generateErrorResponse(error);
  }
}
