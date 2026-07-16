import { createHash, randomBytes } from "crypto";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueCollection } from "@/lib/db/schema";
import {
  isPublishedR2Configured,
  publishedObjectPublicUrl,
  putPublishedObject,
} from "@/lib/storage/published-r2";

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
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/thumbnail">
) {
  const { collectionId } = await ctx.params;

  if (!isPublishedR2Configured()) {
    return NextResponse.json(
      {
        error:
          "Published R2 is not configured. Set R2_PUBLISHED_BUCKET_NAME and R2_PUBLISHED_PUBLIC_BASE_URL.",
      },
      { status: 400 }
    );
  }

  const collection = await db.query.dialogueCollection.findFirst({
    where: eq(dialogueCollection.id, collectionId),
  });
  if (!collection) {
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
  const objectKey = `dialogue/${collectionId}/thumbnail-${hash}.${ext}`;
  await putPublishedObject(objectKey, bytes, contentType);
  const thumbnailUrl = publishedObjectPublicUrl(objectKey);

  const [updated] = await db
    .update(dialogueCollection)
    .set({
      thumbnailUrl,
      updatedAt: new Date(),
    })
    .where(eq(dialogueCollection.id, collectionId))
    .returning();

  return NextResponse.json({ collection: updated, thumbnailUrl, objectKey });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/thumbnail">
) {
  const { collectionId } = await ctx.params;
  const [updated] = await db
    .update(dialogueCollection)
    .set({
      thumbnailUrl: null,
      updatedAt: new Date(),
    })
    .where(eq(dialogueCollection.id, collectionId))
    .returning();
  if (!updated) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ collection: updated });
}
