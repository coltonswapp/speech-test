import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsExport } from "@/lib/db/schema";
import { deleteObject, getObject } from "@/lib/storage/r2";

const contentTypeByFormat: Record<string, string> = {
  wav: "audio/wav",
  mp3: "audio/mpeg",
  m4a: "audio/mp4",
};

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/exports/[exportId]">
) {
  const { exportId } = await ctx.params;
  const record = await db.query.ttsExport.findFirst({
    where: eq(ttsExport.id, exportId),
  });
  if (!record) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const bytes = await getObject(record.objectKey);
  const filename = `take.${record.format}`;

  return new NextResponse(new Uint8Array(bytes), {
    headers: {
      "Content-Type": contentTypeByFormat[record.format] ?? "application/octet-stream",
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
}

export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/exports/[exportId]">
) {
  const { exportId } = await ctx.params;
  const record = await db.query.ttsExport.findFirst({
    where: eq(ttsExport.id, exportId),
  });
  if (!record) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  await deleteObject(record.objectKey);
  await db.delete(ttsExport).where(eq(ttsExport.id, exportId));

  return NextResponse.json({ ok: true });
}
