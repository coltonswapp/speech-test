import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsDialogueLine, ttsProject } from "@/lib/db/schema";
import { updateProjectSchema } from "@/lib/tts/types";

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]">
) {
  const { id } = await ctx.params;
  const project = await db.query.ttsProject.findFirst({
    where: eq(ttsProject.id, id),
  });
  if (!project) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  const dialogueLines = await db.query.ttsDialogueLine.findMany({
    where: eq(ttsDialogueLine.projectId, id),
    orderBy: (line, { asc }) => [asc(line.orderIndex)],
  });
  return NextResponse.json({ project, dialogueLines });
}

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]">
) {
  const { id } = await ctx.params;
  const body = await request.json();
  const parsed = updateProjectSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { dialogueLines, ...projectFields } = parsed.data;

  const [project] = await db
    .update(ttsProject)
    .set({ ...projectFields, updatedAt: new Date() })
    .where(eq(ttsProject.id, id))
    .returning();

  if (!project) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  if (dialogueLines) {
    await db.delete(ttsDialogueLine).where(eq(ttsDialogueLine.projectId, id));
    if (dialogueLines.length > 0) {
      await db.insert(ttsDialogueLine).values(
        dialogueLines.map((line, index) => ({
          projectId: id,
          speaker: line.speaker,
          text: line.text,
          orderIndex: index,
        }))
      );
    }
  }

  return NextResponse.json({ project });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]">
) {
  const { id } = await ctx.params;
  const [deleted] = await db
    .delete(ttsProject)
    .where(eq(ttsProject.id, id))
    .returning({ id: ttsProject.id });
  if (!deleted) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}
