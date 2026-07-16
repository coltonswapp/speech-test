import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { desc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsDialogueGroup, ttsProject, ttsVariant } from "@/lib/db/schema";
import { createProjectSchema } from "@/lib/tts/types";

export async function GET() {
  const [projects, groups] = await Promise.all([
    db.query.ttsProject.findMany({ orderBy: [desc(ttsProject.updatedAt)] }),
    db.query.ttsDialogueGroup.findMany(),
  ]);
  const groupTitleById = new Map(groups.map((g) => [g.id, g.title]));

  const summaries = await Promise.all(
    projects.map(async (project) => {
      const variants = await db.query.ttsVariant.findMany({
        where: eq(ttsVariant.projectId, project.id),
      });
      const selected = variants.find((v) => v.id === project.selectedVariantId);
      return {
        id: project.id,
        displayName:
          project.trackName?.trim() ||
          project.promptText.split("\n")[0]?.slice(0, 60) ||
          "Untitled track",
        provider: project.provider,
        voice: project.voice,
        compositionMode: project.compositionMode,
        variantCount: variants.length,
        groupId: project.groupId,
        groupTitle: project.groupId ? groupTitleById.get(project.groupId) ?? null : null,
        groupOrderIndex: project.groupOrderIndex,
        updatedAt: project.updatedAt,
        hasSelectedTake: Boolean(selected),
      };
    })
  );

  return NextResponse.json({ projects: summaries });
}

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = createProjectSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const [project] = await db
    .insert(ttsProject)
    .values({
      promptText: parsed.data.promptText,
      instructions: parsed.data.instructions ?? null,
      provider: parsed.data.provider,
      voice: parsed.data.voice,
      model: parsed.data.model,
      compositionMode: parsed.data.compositionMode,
      trackName: parsed.data.trackName ?? null,
    })
    .returning();

  return NextResponse.json({ project }, { status: 201 });
}
