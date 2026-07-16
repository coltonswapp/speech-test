import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { grammarPoint } from "@/lib/db/schema";
import { contentStatusSchema } from "@/lib/content/types";

const bodySchema = z.object({
  status: contentStatusSchema,
  reviewNotes: z.string().nullable().optional(),
});

export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/content/points/[id]/status">
) {
  const { id } = await ctx.params;
  const body = await request.json();
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const [point] = await db
    .update(grammarPoint)
    .set({
      status: parsed.data.status,
      reviewNotes: parsed.data.reviewNotes,
      updatedAt: new Date(),
    })
    .where(eq(grammarPoint.id, id))
    .returning();

  if (!point) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ point });
}
