import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  checkOffContentQaRequestSchema,
  contentQaReadinessSlice,
} from "@/lib/dialogue/content-qa";
import {
  ContentQaNotFoundError,
  checkOffContentQa,
} from "@/lib/dialogue/content-qa-store";

type RouteCtx = {
  params: Promise<{ collectionId: string; slug: string }>;
};

/**
 * Scene check-off for the learner client.
 *
 * Marks the scene as fully reviewed (dialogue + quiz). Idempotent.
 * Auth: Bearer CONTENT_QA_CLIENT_TOKEN (or STUDIO_AGENT_TOKEN / Studio session).
 * Contract: docs/studio-content-qa-review.md §3.0
 */
export async function POST(request: NextRequest, ctx: RouteCtx) {
  const { collectionId, slug } = await ctx.params;
  const scenarioId = `${collectionId}/${slug}`;

  let body: unknown = {};
  const contentType = request.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    try {
      const parsedJson = await request.json();
      body = parsedJson === null || parsedJson === undefined ? {} : parsedJson;
    } catch {
      return NextResponse.json({ error: "Invalid JSON body." }, { status: 400 });
    }
  }

  const parsed = checkOffContentQaRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 },
    );
  }

  try {
    const { record, created, alreadyCheckedOff } = await checkOffContentQa(
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
