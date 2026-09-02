import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getPublicDialogueCollectionFile } from "@/lib/dialogue/public-api";

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/public/dialogues/[collectionId]">
) {
  const { collectionId } = await ctx.params;
  const file = await getPublicDialogueCollectionFile(collectionId);
  if (!file) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json(file, {
    headers: {
      // Lesson JSON includes token karaoke; edge cache would keep the app on
      // a pre-stamp snapshot for minutes after publish.
      "Cache-Control": "private, no-store",
    },
  });
}
