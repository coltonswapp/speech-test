import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { bearerMatches, contentQaClientTokenMatches } from "@/lib/studio-auth";
import { GEMINI_VOICE_CATALOG } from "@/lib/tts/gemini-voice-catalog";
import { uploadVoiceTake, VoiceTakeUploadError } from "@/lib/tts/voice-takes-batch";
import { r2VoiceTakeStore } from "@/lib/tts/voice-takes-gemini";

// Auth: proxy.ts gates every non-public /api route (passphrase, Google
// session, or API bearer), same as generate. Scripts send
// `Authorization: Bearer $STUDIO_AGENT_TOKEN`. The learner-app content-QA
// token also passes proxy.ts, so it is refused here: it must not write takes.

// A take is ~300 KB; well under Vercel's request body limit.
const MAX_BYTES = 4_000_000;

/**
 * Upload one pre-generated voice take (raw `audio/wav` body):
 *   POST /api/tts/voice-takes/upload?voice=Kore&take=1&model=gemini-3.8-flash-tts[&overwrite=1]
 * Writes the same R2 key and manifest entry as "Generate missing takes".
 * Existing takes return status "skipped" unless overwrite=1.
 */
export async function POST(request: NextRequest) {
  const authorization = request.headers.get("authorization");
  if (contentQaClientTokenMatches(authorization) && !bearerMatches(authorization)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const params = request.nextUrl.searchParams;
  const declared = Number(request.headers.get("content-length") ?? 0);
  if (declared > MAX_BYTES) {
    return NextResponse.json({ error: "Take too large" }, { status: 413 });
  }
  const wav = Buffer.from(await request.arrayBuffer());
  if (wav.length === 0 || wav.length > MAX_BYTES) {
    return NextResponse.json({ error: "Body must be one WAV take" }, { status: 400 });
  }

  try {
    const result = await uploadVoiceTake({
      store: r2VoiceTakeStore,
      catalog: GEMINI_VOICE_CATALOG,
      voice: params.get("voice") ?? "",
      take: Number(params.get("take")),
      model: params.get("model") ?? "",
      wav,
      overwrite: params.get("overwrite") === "1",
    });
    const { manifest, ...rest } = result;
    const voiceEntry = manifest.voices.find((v) => v.voice === result.voice);
    return NextResponse.json({ ...rest, voiceTakes: voiceEntry?.takes.length ?? 0 });
  } catch (error) {
    if (error instanceof VoiceTakeUploadError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    throw error;
  }
}
