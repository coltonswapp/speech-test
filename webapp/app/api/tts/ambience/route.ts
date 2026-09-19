import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ambienceAsset } from "@/lib/db/schema";
import { putObject } from "@/lib/storage/r2";
import { probeAudioMetadata } from "@/lib/tts/audio-encode";
import { normalizeAmbienceKind } from "@/lib/tts/ambience";

const MAX_BYTES = 20 * 1024 * 1024;

const ALLOWED_TYPES = new Map<string, string>([
  ["audio/wav", "wav"],
  ["audio/wave", "wav"],
  ["audio/x-wav", "wav"],
  ["audio/mpeg", "mp3"],
  ["audio/mp3", "mp3"],
  ["audio/mp4", "m4a"],
  ["audio/m4a", "m4a"],
  ["audio/x-m4a", "m4a"],
  ["audio/aac", "m4a"],
  ["audio/ogg", "ogg"],
  ["audio/flac", "flac"],
]);

const EXT_FROM_NAME: Record<string, string> = {
  wav: "wav",
  wave: "wav",
  mp3: "mp3",
  m4a: "m4a",
  aac: "m4a",
  mp4: "m4a",
  ogg: "ogg",
  flac: "flac",
};

export async function GET() {
  const assets = await db.query.ambienceAsset.findMany({
    orderBy: [asc(ambienceAsset.kind), asc(ambienceAsset.title)],
  });
  return NextResponse.json({ assets });
}

export async function POST(request: NextRequest) {
  const formData = await request.formData();
  const file = formData.get("file");
  const titleRaw = String(formData.get("title") ?? "").trim();
  const kind = normalizeAmbienceKind(String(formData.get("kind") ?? "other"));

  if (!(file instanceof File)) {
    return NextResponse.json(
      { error: "Expected multipart field “file”." },
      { status: 400 }
    );
  }
  if (!titleRaw) {
    return NextResponse.json({ error: "Give the bed a title." }, { status: 400 });
  }
  if (file.size > MAX_BYTES) {
    return NextResponse.json(
      { error: "Ambience file must be 20 MB or smaller." },
      { status: 400 }
    );
  }

  const contentType = (file.type || "").toLowerCase();
  const nameExt = file.name.split(".").pop()?.toLowerCase() ?? "";
  const ext =
    ALLOWED_TYPES.get(contentType) ?? EXT_FROM_NAME[nameExt] ?? null;
  if (!ext) {
    return NextResponse.json(
      { error: "Use a WAV, MP3, or M4A loop." },
      { status: 400 }
    );
  }

  const bytes = Buffer.from(await file.arrayBuffer());
  let meta;
  try {
    meta = await probeAudioMetadata(bytes);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Could not read that audio file.";
    return NextResponse.json({ error: message }, { status: 400 });
  }

  const id = crypto.randomUUID();
  const audioObjectKey = `ambience/${id}.${ext}`;
  await putObject(audioObjectKey, bytes, contentType || `audio/${ext}`);

  const [asset] = await db
    .insert(ambienceAsset)
    .values({
      id,
      title: titleRaw,
      kind,
      audioObjectKey,
      contentType: contentType || `audio/${ext}`,
      durationSeconds: meta.durationSeconds,
      sampleRate: meta.sampleRate,
      byteCount: bytes.length,
    })
    .returning();

  return NextResponse.json({ asset });
}
