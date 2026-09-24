import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  contentQaReadinessSlice,
  upsertContentQaRequestSchema,
} from "@/lib/dialogue/content-qa";
import {
  ContentQaNotFoundError,
  getContentQaByScenarioId,
  upsertContentQa,
} from "@/lib/dialogue/content-qa-store";

type RouteCtx = {
  params: Promise<{ collectionId: string; slug: string }>;
};

function scenarioIdFromParams(collectionId: string, slug: string): string {
  return `${collectionId}/${slug}`;
}

function pendingReview(collectionId: string, slug: string) {
  const scenarioId = scenarioIdFromParams(collectionId, slug);
  return {
    scenarioId,
    collectionId,
    dialogueReviewedAt: null,
    quizReviewedAt: null,
    reviewNote: null,
    reviewedBy: null,
    status: "pending" as const,
    checkedOff: false,
    createdAt: null,
    updatedAt: null,
  };
}

/**
 * Learner-client content QA for one scenario (granular get/upsert).
 *
 * For the primary “mark scene reviewed / checked off” action, prefer
 * POST …/check-off — see docs/studio-content-qa-review.md §3.0.
 *
 * Auth (when Studio auth is enforced): Google session, `STUDIO_AGENT_TOKEN`,
 * or `CONTENT_QA_CLIENT_TOKEN` Bearer. Not a public unauthenticated write.
 */
export async function GET(_request: NextRequest, ctx: RouteCtx) {
  const { collectionId, slug } = await ctx.params;
  const scenarioId = scenarioIdFromParams(collectionId, slug);

  const record = await getContentQaByScenarioId(scenarioId);
  if (!record) {
    const review = pendingReview(collectionId, slug);
    return NextResponse.json({
      review,
      readiness: contentQaReadinessSlice({
        status: "pending",
        reviewNote: null,
        checkedOff: false,
      }),
    });
  }
  return NextResponse.json({
    review: record,
    readiness: contentQaReadinessSlice(record),
  });
}

/** Idempotent upsert (prefer PUT). Same body as PATCH. */
export async function PUT(request: NextRequest, ctx: RouteCtx) {
  return upsert(request, ctx);
}

export async function PATCH(request: NextRequest, ctx: RouteCtx) {
  return upsert(request, ctx);
}

async function upsert(request: NextRequest, ctx: RouteCtx) {
  const { collectionId, slug } = await ctx.params;
  const scenarioId = scenarioIdFromParams(collectionId, slug);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body." }, { status: 400 });
  }

  const parsed = upsertContentQaRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 },
    );
  }

  try {
    const { record, created, alreadyCheckedOff } = await upsertContentQa(
      scenarioId,
      parsed.data,
    );
    return NextResponse.json(
      {
        review: record,
        readiness: contentQaReadinessSlice(record),
        created,
        alreadyCheckedOff,
      },
      { status: created ? 201 : 200 },
    );
  } catch (error) {
    if (error instanceof ContentQaNotFoundError) {
      return NextResponse.json({ error: error.message }, { status: 404 });
    }
    throw error;
  }
}
