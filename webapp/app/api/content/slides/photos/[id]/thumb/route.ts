import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { slideshowPhoto } from "@/lib/db/schema";
import { getObject } from "@/lib/storage/r2";

export async function GET(
  _request: Request,
  ctx: RouteContext<"/api/content/slides/photos/[id]/thumb">
) {
  const { id } = await ctx.params;
  const photo = await db.query.slideshowPhoto.findFirst({
    where: eq(slideshowPhoto.id, id),
  });
  if (!photo) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  const bytes = await getObject(photo.thumbObjectKey);
  return new NextResponse(new Uint8Array(bytes), {
    headers: {
      "Content-Type": photo.contentType,
      "Content-Length": String(bytes.length),
      "Cache-Control": "private, max-age=3600",
    },
  });
}
