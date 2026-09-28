import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { listVoiceProfiles } from "@/lib/tts/voice-profiles";

const querySchema = z.object({
  provider: z.string().min(1).default("gemini"),
});

export async function GET(request: NextRequest) {
  const parsed = querySchema.safeParse({
    provider: request.nextUrl.searchParams.get("provider") ?? undefined,
  });
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const profiles = await listVoiceProfiles(parsed.data.provider);
  return NextResponse.json({ profiles });
}
