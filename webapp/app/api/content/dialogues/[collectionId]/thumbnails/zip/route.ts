import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueCollection, dialogueScenario } from "@/lib/db/schema";
import {
  contentDispositionAttachment,
  zipLessonThumbnails,
} from "@/lib/dialogue/lesson-thumbnail-download";
import {
  buildLessonThumbnailItems,
  slugifyFilenamePart,
} from "@/lib/dialogue/lesson-thumbnails";

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/thumbnails/zip">
) {
  const { collectionId } = await ctx.params;

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

  const zipped = await zipLessonThumbnails(items);
  if (!zipped) {
    return NextResponse.json(
      { error: "No thumbnails to download." },
      { status: 404 }
    );
  }

  const filename = `${slugifyFilenamePart(collection.id)}-thumbnails.zip`;
  return new NextResponse(new Uint8Array(zipped.buffer), {
    headers: {
      "Content-Type": "application/zip",
      "Content-Disposition": contentDispositionAttachment(filename),
    },
  });
}
