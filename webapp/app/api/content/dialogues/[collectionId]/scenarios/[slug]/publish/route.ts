import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  publishScenarioAudio,
  unpublishScenarioAudio,
} from "@/lib/dialogue/publish";

export async function POST(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]/publish">
) {
  const { collectionId, slug } = await ctx.params;
  try {
    const result = await publishScenarioAudio(collectionId, slug);
    return NextResponse.json({
      scenario: result.scenario,
      publishedAudioUrl: result.publishedAudioUrl,
      objectKey: result.objectKey,
      hasTokenKaraoke: result.hasTokenKaraoke,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Publish failed";
    const status = message.includes("not found") ? 404 : 400;
    return NextResponse.json({ error: message }, { status });
  }
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/scenarios/[slug]/publish">
) {
  const { collectionId, slug } = await ctx.params;
  try {
    const scenario = await unpublishScenarioAudio(collectionId, slug);
    return NextResponse.json({ scenario });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unpublish failed";
    const status = message.includes("not found") ? 404 : 400;
    return NextResponse.json({ error: message }, { status });
  }
}
