import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { teachingPattern } from "@/lib/db/schema";
import {
  normalizeTeachingPatternUpdate,
  teachingPatternUpdateSchema,
} from "@/lib/patterns/schema";

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/content/patterns/[id]">
) {
  const { id } = await ctx.params;
  let json: unknown;
  try {
    json = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const parsed = teachingPatternUpdateSchema.safeParse(json);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    return NextResponse.json(
      {
        error: issue
          ? `${issue.path.join(".") || "body"}: ${issue.message}`
          : "Invalid pattern body",
      },
      { status: 400 }
    );
  }

  const fields = normalizeTeachingPatternUpdate(parsed.data);
  const [pattern] = await db
    .update(teachingPattern)
    .set({ ...fields, updatedAt: new Date() })
    .where(eq(teachingPattern.id, id))
    .returning();

  if (!pattern) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ pattern });
}
