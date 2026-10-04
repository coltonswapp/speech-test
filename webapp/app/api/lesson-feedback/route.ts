import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getFirebaseAdminStatus } from "@/lib/usage/firebase-admin";
import {
  LessonFeedbackFirestoreError,
  readLowestRatedScenes,
  readScenarioFeedback,
} from "@/lib/lesson-feedback/firestore";

/**
 * Studio-only learner ratings for dialogue scenes (read-only).
 *
 * With `collectionId` + `scenarioId`: one scene's stats and recent ratings.
 * Without: every rated scene, weakest dimension first.
 * Auth is enforced by `proxy.ts`, same as `/api/usage`.
 */

const segment = z
  .string()
  .trim()
  .min(1)
  .max(120)
  .regex(/^[A-Za-z0-9._-]+$/, "unsupported characters");

const querySchema = z.object({
  collectionId: segment.optional(),
  scenarioId: segment.optional(),
  limit: z.coerce.number().int().min(1).max(200).optional(),
});

export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const parsed = querySchema.safeParse({
    collectionId: params.get("collectionId") ?? undefined,
    scenarioId: params.get("scenarioId") ?? undefined,
    limit: params.get("limit") ?? undefined,
  });
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const { collectionId, scenarioId, limit } = parsed.data;
  if (Boolean(collectionId) !== Boolean(scenarioId)) {
    return NextResponse.json(
      { error: "collectionId and scenarioId must be passed together" },
      { status: 400 },
    );
  }

  const status = getFirebaseAdminStatus();
  if (!status.ok) {
    return NextResponse.json({ configured: false, configError: status.reason });
  }

  try {
    if (collectionId && scenarioId) {
      const scene = await readScenarioFeedback(collectionId, scenarioId);
      return NextResponse.json({ configured: true, configError: null, scene });
    }
    const overview = await readLowestRatedScenes(limit);
    return NextResponse.json({ configured: true, configError: null, overview });
  } catch (err) {
    if (err instanceof LessonFeedbackFirestoreError) {
      const statusCode = err.code === "not_configured" ? 503 : 502;
      return NextResponse.json(
        { error: err.message, code: err.code },
        { status: statusCode },
      );
    }
    const message =
      err instanceof Error ? err.message : "Failed to load lesson feedback";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
