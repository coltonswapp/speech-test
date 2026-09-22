import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { slideshowPhoto } from "@/lib/db/schema";
import { deleteObject } from "@/lib/storage/r2";
import { serializePhoto } from "@/lib/slides/store";

const updateSchema = z.object({
  title: z.string().min(1).optional(),
  tags: z.array(z.string()).optional(),
});

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/content/slides/photos/[id]">
) {
  const { id } = await ctx.params;
  const body = await request.json().catch(() => ({}));
  const parsed = updateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  if (Object.keys(parsed.data).length === 0) {
    return NextResponse.json({ error: "Nothing to update." }, { status: 400 });
  }
  const tags = parsed.data.tags?.map((tag) => tag.trim().toLowerCase()).filter(Boolean);
  const [row] = await db
    .update(slideshowPhoto)
    .set({
      ...(parsed.data.title ? { title: parsed.data.title } : {}),
      ...(tags ? { tags } : {}),
      updatedAt: new Date(),
    })
    .where(eq(slideshowPhoto.id, id))
    .returning();
  if (!row) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ photo: serializePhoto(row) });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/slides/photos/[id]">
) {
  const { id } = await ctx.params;
  const existing = await db.query.slideshowPhoto.findFirst({
    where: eq(slideshowPhoto.id, id),
  });
  if (!existing) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  await db.delete(slideshowPhoto).where(eq(slideshowPhoto.id, id));
  await Promise.all([
    deleteObject(existing.objectKey).catch(() => undefined),
    deleteObject(existing.thumbObjectKey).catch(() => undefined),
  ]);
  return NextResponse.json({ ok: true });
}
