import { NextResponse } from "next/server";
import { getObject } from "@/lib/storage/r2";
import { voiceTakesManifestKey, voiceTakesManifestSchema } from "@/lib/tts/voice-takes";

function isMissingObject(error: unknown): boolean {
  const e = error as { name?: string; $metadata?: { httpStatusCode?: number } };
  return e?.name === "NoSuchKey" || e?.$metadata?.httpStatusCode === 404;
}

/** Voice-takes manifest from R2, or null until scripts/seed-voice-takes.ts has run. */
export async function GET() {
  try {
    const raw = await getObject(voiceTakesManifestKey());
    const parsed = voiceTakesManifestSchema.safeParse(JSON.parse(raw.toString("utf8")));
    if (!parsed.success) {
      return NextResponse.json({ error: "Voice takes manifest is invalid." }, { status: 500 });
    }
    return NextResponse.json({ manifest: parsed.data });
  } catch (error) {
    if (isMissingObject(error)) return NextResponse.json({ manifest: null });
    throw error;
  }
}
