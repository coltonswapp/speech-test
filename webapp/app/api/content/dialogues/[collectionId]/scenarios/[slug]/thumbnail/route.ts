import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueScenario } from "@/lib/db/schema";
import { publishThumbnail } from "@/lib/images/thumbnail-variants";
import { isPublishedR2Configured } from "@/lib/storage/published-r2";

// Per-scenario thumbnail override. Mirrors the collection-level route at
// ../../../thumbnail/route.ts; the app falls back to the collection's
// thumbnail whenever a scenario has none.

const ALLOWED_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
  "image/gif",
]);

const MAX_BYTES = 5 * 1024 * 1024;

export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]/thumbnail">
) {
  const { collectionId, slug } = await ctx.params;
  const scenarioId = `${collectionId}/${slug}`;

  if (!isPublishedR2Configured()) {
    return NextResponse.json(
      {
        error:
          "Published R2 is not configured. Set R2_PUBLISHED_BUCKET_NAME and R2_PUBLISHED_PUBLIC_BASE_URL.",
      },
      { status: 400 }
    );
  }

  const scenario = await db.query.dialogueScenario.findFirst({
    where: eq(dialogueScenario.id, scenarioId),
  });
  if (!scenario) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const formData = await request.formData();
  const file = formData.get("file");
  if (!(file instanceof File)) {
    return NextResponse.json(
      { error: "Expected multipart field “file”." },
      { status: 400 }
    );
  }

  const contentType = (file.type || "").toLowerCase();
  if (!ALLOWED_TYPES.has(contentType)) {
    return NextResponse.json(
      { error: "Use a JPEG, PNG, WebP, or GIF image." },
      { status: 400 }
    );
  }
  if (file.size > MAX_BYTES) {
    return NextResponse.json(
      { error: "Thumbnail must be 5 MB or smaller." },
      { status: 400 }
    );
  }

  const published = await publishThumbnail(
    `dialogue/${collectionId}/${slug}/thumbnail`,
    Buffer.from(await file.arrayBuffer())
  );

  const [updated] = await db
    .update(dialogueScenario)
    .set({
      thumbnailUrl: published.thumbnailUrl,
      thumbnailSmallUrl: published.thumbnailSmallUrl,
      updatedAt: new Date(),
    })
    .where(eq(dialogueScenario.id, scenarioId))
    .returning();

  return NextResponse.json({
    scenario: updated,
    thumbnailUrl: published.thumbnailUrl,
    thumbnailSmallUrl: published.thumbnailSmallUrl,
    objectKey: published.objectKey,
  });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]/thumbnail">
) {
  const { collectionId, slug } = await ctx.params;
  const [updated] = await db
    .update(dialogueScenario)
    .set({
      thumbnailUrl: null,
      thumbnailSmallUrl: null,
      updatedAt: new Date(),
    })
    .where(eq(dialogueScenario.id, `${collectionId}/${slug}`))
    .returning();
  if (!updated) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ scenario: updated });
}
