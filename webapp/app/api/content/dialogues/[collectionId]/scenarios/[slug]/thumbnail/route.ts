import { createHash, randomBytes } from "crypto";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueScenario } from "@/lib/db/schema";
import {
  isPublishedR2Configured,
  publishedObjectPublicUrl,
  putPublishedObject,
} from "@/lib/storage/published-r2";

// Per-scenario thumbnail override. Mirrors the collection-level route at
// ../../../thumbnail/route.ts; the app falls back to the collection's
// thumbnail whenever a scenario has none.

const ALLOWED_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/jpg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
};

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
  const ext = ALLOWED_TYPES[contentType];
  if (!ext) {
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

  const bytes = Buffer.from(await file.arrayBuffer());
  const hash = createHash("sha256")
    .update(bytes)
    .update(randomBytes(4))
    .digest("hex")
    .slice(0, 12);
  const objectKey = `dialogue/${collectionId}/${slug}/thumbnail-${hash}.${ext}`;
  await putPublishedObject(objectKey, bytes, contentType);
  const thumbnailUrl = publishedObjectPublicUrl(objectKey);

  const [updated] = await db
    .update(dialogueScenario)
    .set({
      thumbnailUrl,
      updatedAt: new Date(),
    })
    .where(eq(dialogueScenario.id, scenarioId))
    .returning();

  return NextResponse.json({ scenario: updated, thumbnailUrl, objectKey });
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
      updatedAt: new Date(),
    })
    .where(eq(dialogueScenario.id, `${collectionId}/${slug}`))
    .returning();
  if (!updated) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ scenario: updated });
}
