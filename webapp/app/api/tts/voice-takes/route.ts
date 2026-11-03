import { NextResponse } from "next/server";
import { readVoiceTakesManifest } from "@/lib/tts/voice-takes-gemini";

/** Voice-takes manifest from R2, or null until "Generate missing takes" has run. */
export async function GET() {
  return NextResponse.json({ manifest: await readVoiceTakesManifest() });
}
