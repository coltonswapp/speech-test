import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import {
  listVoicePairRatings,
  pairRatingSchema,
  sortedVoicePair,
  upsertVoicePairRating,
  voiceGenderSchema,
} from "@/lib/tts/voice-profiles";

const listQuerySchema = z.object({
  provider: z.string().min(1).default("gemini"),
  gender: voiceGenderSchema.optional(),
});

const upsertSchema = z.object({
  provider: z.string().min(1).default("gemini"),
  voiceA: z.string().min(1),
  voiceB: z.string().min(1),
  rating: pairRatingSchema.nullable(),
  notes: z.string().nullable().optional(),
});

export async function GET(request: NextRequest) {
  const params = Object.fromEntries(request.nextUrl.searchParams.entries());
  const parsed = listQuerySchema.safeParse({
    provider: params.provider || undefined,
    gender: params.gender || undefined,
  });
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const ratings = await listVoicePairRatings(parsed.data);
  return NextResponse.json({ ratings });
}

export async function PUT(request: NextRequest) {
  const body = await request.json().catch(() => ({}));
  const parsed = upsertSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const [voiceA, voiceB] = sortedVoicePair(
    parsed.data.voiceA,
    parsed.data.voiceB
  );
  if (voiceA === voiceB) {
    return NextResponse.json(
      { error: "Pick two different voices." },
      { status: 400 }
    );
  }

  try {
    const rating = await upsertVoicePairRating({
      provider: parsed.data.provider,
      voiceA,
      voiceB,
      rating: parsed.data.rating,
      notes: parsed.data.notes,
    });
    return NextResponse.json({ rating });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Could not save pair rating.";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
