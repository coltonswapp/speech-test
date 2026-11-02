import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getObject } from "@/lib/storage/r2";
import { geminiVoiceEntry } from "@/lib/tts/gemini-voice-catalog";
import { VOICE_TAKES_PER_VOICE, voiceTakeObjectKey } from "@/lib/tts/voice-takes";

export async function GET(request: NextRequest) {
  const voice = request.nextUrl.searchParams.get("voice") ?? "";
  const take = Number(request.nextUrl.searchParams.get("take"));
  // Only catalog voices and known take numbers map to keys (no free-form paths).
  if (!geminiVoiceEntry(voice) || !Number.isInteger(take) || take < 1 || take > VOICE_TAKES_PER_VOICE) {
    return NextResponse.json({ error: "Unknown voice take" }, { status: 404 });
  }
  let wav: Buffer;
  try {
    wav = await getObject(voiceTakeObjectKey(voice, take));
  } catch {
    return NextResponse.json({ error: "Voice take not seeded" }, { status: 404 });
  }
  return new NextResponse(new Uint8Array(wav), {
    headers: {
      "Content-Type": "audio/wav",
      "Content-Length": String(wav.length),
      "Cache-Control": "private, max-age=86400",
    },
  });
}
