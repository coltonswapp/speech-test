import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import {
  updateVoiceProfile,
  voiceGenderSchema,
} from "@/lib/tts/voice-profiles";

const patchSchema = z
  .object({
    gender: voiceGenderSchema.optional(),
    notes: z.string().optional(),
  })
  .refine((body) => body.gender !== undefined || body.notes !== undefined, {
    message: "Provide gender and/or notes.",
  });

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/voices/[id]">
) {
  const { id } = await ctx.params;
  const body = await request.json().catch(() => ({}));
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const profile = await updateVoiceProfile(id, parsed.data);
  if (!profile) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ profile });
}
