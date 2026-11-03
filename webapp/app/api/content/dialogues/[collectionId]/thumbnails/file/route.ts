import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueCollection, dialogueScenario } from "@/lib/db/schema";
import {
  contentDispositionAttachment,
  extensionForThumbnail,
  fetchRemoteThumbnail,
} from "@/lib/dialogue/lesson-thumbnail-download";
import { buildLessonThumbnailItems } from "@/lib/dialogue/lesson-thumbnails";

export async function GET(
  request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/thumbnails/file">
) {
  const { collectionId } = await ctx.params;
  const kind = request.nextUrl.searchParams.get("kind");
  const slug = request.nextUrl.searchParams.get("slug");

  if (kind !== "lesson" && kind !== "scene") {
    return NextResponse.json(
      { error: "Query kind must be “lesson” or “scene”." },
      { status: 400 }
    );
  }
  if (kind === "scene" && !slug) {
    return NextResponse.json(
      { error: "Scene downloads need a slug." },
      { status: 400 }
    );
  }

  const collection = await db.query.dialogueCollection.findFirst({
    where: eq(dialogueCollection.id, collectionId),
  });
  if (!collection) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const scenarios = await db.query.dialogueScenario.findMany({
    where: eq(dialogueScenario.collectionId, collectionId),
    orderBy: [asc(dialogueScenario.orderIndex)],
  });

  const items = buildLessonThumbnailItems({
    collectionId: collection.id,
    lessonTitle: collection.title,
    lessonThumbnailUrl: collection.thumbnailUrl,
    lessonThumbnailSmallUrl: collection.thumbnailSmallUrl,
    scenarios,
  });

  const item =
    kind === "lesson"
      ? items.find((entry) => entry.kind === "lesson")
      : items.find((entry) => entry.kind === "scene" && entry.slug === slug);

  if (!item?.thumbnailUrl) {
    return NextResponse.json(
      { error: "No thumbnail for that item." },
      { status: 404 }
    );
  }

  try {
    const { bytes, contentType } = await fetchRemoteThumbnail(item.thumbnailUrl);
    const filename = `${item.filenameBase}.${extensionForThumbnail(contentType, item.thumbnailUrl)}`;
    return new NextResponse(new Uint8Array(bytes), {
      headers: {
        "Content-Type": contentType,
        "Content-Disposition": contentDispositionAttachment(filename),
        "Cache-Control": "private, max-age=300",
      },
    });
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Could not fetch thumbnail.",
      },
      { status: 502 }
    );
  }
}
