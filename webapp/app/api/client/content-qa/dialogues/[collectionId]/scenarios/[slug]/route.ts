import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { upsertContentQaRequestSchema } from "@/lib/dialogue/content-qa";
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

/**
 * Learner-client content QA for one scenario.
 *
 * Auth (when Studio auth is enforced): Google session, `STUDIO_AGENT_TOKEN`,
 * or `CONTENT_QA_CLIENT_TOKEN` Bearer — see docs/studio-content-qa-review.md.
 * Not a public unauthenticated write.
 */
export async function GET(_request: NextRequest, ctx: RouteCtx) {
  const { collectionId, slug } = await ctx.params;
  const scenarioId = scenarioIdFromParams(collectionId, slug);

  const record = await getContentQaByScenarioId(scenarioId);
  if (!record) {
    return NextResponse.json({
      review: {
        scenarioId,
        collectionId,
        dialogueReviewedAt: null,
        quizReviewedAt: null,
        reviewNote: null,
        reviewedBy: null,
        status: "pending" as const,
        createdAt: null,
        updatedAt: null,
      },
    });
  }
  return NextResponse.json({ review: record });
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
    const { record, created } = await upsertContentQa(scenarioId, parsed.data);
    return NextResponse.json(
      { review: record, created },
      { status: created ? 201 : 200 },
    );
  } catch (error) {
    if (error instanceof ContentQaNotFoundError) {
      return NextResponse.json({ error: error.message }, { status: 404 });
    }
    throw error;
  }
}
