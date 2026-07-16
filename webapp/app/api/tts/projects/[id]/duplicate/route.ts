import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsDialogueLine, ttsProject } from "@/lib/db/schema";

export async function POST(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/duplicate">
) {
  const { id } = await ctx.params;

  const source = await db.query.ttsProject.findFirst({
    where: eq(ttsProject.id, id),
  });
  if (!source) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const sourceLines = await db.query.ttsDialogueLine.findMany({
    where: eq(ttsDialogueLine.projectId, id),
    orderBy: (line, { asc }) => [asc(line.orderIndex)],
  });

  const [copy] = await db
    .insert(ttsProject)
    .values({
      promptText: source.promptText,
      instructions: source.instructions,
      provider: source.provider,
      voice: source.voice,
      model: source.model,
      compositionMode: source.compositionMode,
      speaker1Voice: source.speaker1Voice,
      speaker2Voice: source.speaker2Voice,
      speaker1Name: source.speaker1Name,
      speaker2Name: source.speaker2Name,
      trackName: source.trackName ? `${source.trackName} copy` : null,
      // Intentionally not copied: groupId/groupOrderIndex/sourceScenarioId/selectedVariantId —
      // a duplicate is a fresh, ungrouped track, not a re-imported scenario.
    })
    .returning();

  if (sourceLines.length > 0) {
    await db.insert(ttsDialogueLine).values(
      sourceLines.map((line) => ({
        projectId: copy.id,
        speaker: line.speaker,
        text: line.text,
        orderIndex: line.orderIndex,
      }))
    );
  }

  return NextResponse.json({ project: copy }, { status: 201 });
}
