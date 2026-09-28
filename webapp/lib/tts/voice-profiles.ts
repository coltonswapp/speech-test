import { and, asc, eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { ttsVoicePairRating, ttsVoiceProfile } from "@/lib/db/schema";
import { GEMINI_TTS_VOICES } from "@/lib/tts/gemini-voices";

export const VOICE_GENDERS = ["female", "male", "neutral", "unknown"] as const;
export type VoiceGender = (typeof VOICE_GENDERS)[number];

export const PAIR_RATINGS = ["green", "yellow", "red"] as const;
export type PairRating = (typeof PAIR_RATINGS)[number];

export const voiceGenderSchema = z.enum(VOICE_GENDERS);
export const pairRatingSchema = z.enum(PAIR_RATINGS);

const GEMINI_PROVIDER = "gemini";

/** Lexicographic order so (A,B) and (B,A) share one row. */
export function sortedVoicePair(
  voiceA: string,
  voiceB: string
): [string, string] {
  return voiceA < voiceB ? [voiceA, voiceB] : [voiceB, voiceA];
}

/** Insert any Gemini catalog voices that are missing from tts_voice_profile. */
export async function seedMissingGeminiVoiceProfiles(): Promise<void> {
  const existing = await db.query.ttsVoiceProfile.findMany({
    columns: { voice: true },
    where: eq(ttsVoiceProfile.provider, GEMINI_PROVIDER),
  });
  const have = new Set(existing.map((row) => row.voice));
  const missing = GEMINI_TTS_VOICES.filter((voice) => !have.has(voice));
  if (missing.length === 0) return;

  await db.insert(ttsVoiceProfile).values(
    missing.map((voice) => ({
      provider: GEMINI_PROVIDER,
      voice,
      gender: "unknown" as const,
      notes: "",
    }))
  );
}

export async function listVoiceProfiles(provider = GEMINI_PROVIDER) {
  if (provider === GEMINI_PROVIDER) {
    await seedMissingGeminiVoiceProfiles();
  }
  return db.query.ttsVoiceProfile.findMany({
    where: eq(ttsVoiceProfile.provider, provider),
    orderBy: [asc(ttsVoiceProfile.voice)],
  });
}

export async function listVoicePairRatings(opts: {
  provider?: string;
  gender?: VoiceGender;
}) {
  const provider = opts.provider ?? GEMINI_PROVIDER;
  const ratings = await db.query.ttsVoicePairRating.findMany({
    where: eq(ttsVoicePairRating.provider, provider),
    orderBy: [asc(ttsVoicePairRating.voiceA), asc(ttsVoicePairRating.voiceB)],
  });

  if (!opts.gender) return ratings;

  const profiles = await db.query.ttsVoiceProfile.findMany({
    columns: { voice: true },
    where: and(
      eq(ttsVoiceProfile.provider, provider),
      eq(ttsVoiceProfile.gender, opts.gender)
    ),
  });
  const allowed = new Set(profiles.map((row) => row.voice));
  return ratings.filter(
    (row) => allowed.has(row.voiceA) && allowed.has(row.voiceB)
  );
}

export async function upsertVoicePairRating(input: {
  provider: string;
  voiceA: string;
  voiceB: string;
  rating: PairRating | null;
  notes?: string | null;
}) {
  const [voiceA, voiceB] = sortedVoicePair(input.voiceA, input.voiceB);
  if (voiceA === voiceB) {
    throw new Error("Pick two different voices.");
  }

  if (input.rating === null) {
    await db
      .delete(ttsVoicePairRating)
      .where(
        and(
          eq(ttsVoicePairRating.provider, input.provider),
          eq(ttsVoicePairRating.voiceA, voiceA),
          eq(ttsVoicePairRating.voiceB, voiceB)
        )
      );
    return null;
  }

  const conflictSet: {
    rating: PairRating;
    notes?: string | null;
    updatedAt: Date;
  } = {
    rating: input.rating,
    updatedAt: new Date(),
  };
  if (input.notes !== undefined) {
    conflictSet.notes = input.notes;
  }

  const [row] = await db
    .insert(ttsVoicePairRating)
    .values({
      provider: input.provider,
      voiceA,
      voiceB,
      rating: input.rating,
      notes: input.notes ?? null,
      updatedAt: new Date(),
    })
    .onConflictDoUpdate({
      target: [
        ttsVoicePairRating.provider,
        ttsVoicePairRating.voiceA,
        ttsVoicePairRating.voiceB,
      ],
      set: conflictSet,
    })
    .returning();

  return row;
}

export async function updateVoiceProfile(
  id: string,
  patch: { gender?: VoiceGender; notes?: string }
) {
  const set: {
    gender?: VoiceGender;
    notes?: string;
    updatedAt: Date;
  } = { updatedAt: new Date() };
  if (patch.gender !== undefined) set.gender = patch.gender;
  if (patch.notes !== undefined) set.notes = patch.notes;

  const [row] = await db
    .update(ttsVoiceProfile)
    .set(set)
    .where(eq(ttsVoiceProfile.id, id))
    .returning();
  return row ?? null;
}
