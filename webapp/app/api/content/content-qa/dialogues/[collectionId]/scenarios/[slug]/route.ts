import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { upsertContentQaRequestSchema } from "@/lib/dialogue/content-qa";
import {
  ContentQaNotFoundError,
  upsertContentQa,
} from "@/lib/dialogue/content-qa-store";

type RouteCtx = {
  params: Promise<{ collectionId: string; slug: string }>;
};

/**
 * Studio-side content QA upsert (same body as the client route).
 * Useful for seeding / demos before the learner client ships.
 * Auth: Studio session / agent token (standard /api/content/* gate).
 */
export async function PUT(request: NextRequest, ctx: RouteCtx) {
  return upsert(request, ctx);
}

export async function PATCH(request: NextRequest, ctx: RouteCtx) {
  return upsert(request, ctx);
}

async function upsert(request: NextRequest, ctx: RouteCtx) {
  const { collectionId, slug } = await ctx.params;
  const scenarioId = `${collectionId}/${slug}`;

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
