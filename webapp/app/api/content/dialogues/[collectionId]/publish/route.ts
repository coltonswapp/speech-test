import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { publishLesson } from "@/lib/dialogue/publish";

// Publishes a whole lesson (dialogue collection): uploads CDN audio for every
// scenario with a selected take, then returns the full lesson JSON with accurate
// publishedAudioUrl fields for Shizen.

export async function POST(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/publish">
) {
  const { collectionId } = await ctx.params;
  try {
    const result = await publishLesson(collectionId);
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Publish failed";
    const status = message.includes("not found") ? 404 : 400;
    return NextResponse.json({ error: message }, { status });
  }
}
