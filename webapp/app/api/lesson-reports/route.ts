import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getFirebaseAdminStatus } from "@/lib/usage/firebase-admin";
import {
  LessonReportsFirestoreError,
  readScenarioReports,
  updateReportStatus,
} from "@/lib/lesson-reports/firestore";
import { LESSON_REPORT_STATUSES } from "@/lib/lesson-reports/types";

/**
 * Studio-only learner problem reports for dialogue scenes.
 *
 * GET with `collectionId` + `scenarioId`: one scene's counts and recent reports.
 * PATCH `{ reportId, status }`: mark a report open, resolved, or won't fix.
 * Auth is enforced by `proxy.ts`, same as `/api/lesson-feedback`.
 */

const segment = z
  .string()
  .trim()
  .min(1)
  .max(120)
  .regex(/^[A-Za-z0-9._-]+$/, "unsupported characters");

const querySchema = z.object({
  collectionId: segment,
  scenarioId: segment,
});

const patchSchema = z.object({
  reportId: z.uuid(),
  status: z.enum(LESSON_REPORT_STATUSES),
});

function errorResponse(err: unknown, fallback: string) {
  if (err instanceof LessonReportsFirestoreError) {
    const status =
      err.code === "not_configured" ? 503 : err.code === "not_found" ? 404 : 502;
    return NextResponse.json({ error: err.message, code: err.code }, { status });
  }
  const message = err instanceof Error ? err.message : fallback;
  return NextResponse.json({ error: message }, { status: 502 });
}

export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const parsed = querySchema.safeParse({
    collectionId: params.get("collectionId") ?? undefined,
    scenarioId: params.get("scenarioId") ?? undefined,
  });
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const status = getFirebaseAdminStatus();
  if (!status.ok) {
    return NextResponse.json({ configured: false, configError: status.reason });
  }

  try {
    const scene = await readScenarioReports(
      parsed.data.collectionId,
      parsed.data.scenarioId,
    );
    return NextResponse.json({ configured: true, configError: null, scene });
  } catch (err) {
    return errorResponse(err, "Failed to load lesson reports");
  }
}

export async function PATCH(request: NextRequest) {
  const body = await request.json().catch(() => null);
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  try {
    await updateReportStatus(parsed.data.reportId.toLowerCase(), parsed.data.status);
    return NextResponse.json({ ok: true });
  } catch (err) {
    return errorResponse(err, "Failed to update lesson report");
  }
}
