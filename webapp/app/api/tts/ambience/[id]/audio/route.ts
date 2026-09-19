import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ambienceAsset } from "@/lib/db/schema";
import { getObject } from "@/lib/storage/r2";

export async function GET(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/ambience/[id]/audio">
) {
  const { id } = await ctx.params;
  const asset = await db.query.ambienceAsset.findFirst({
    where: eq(ambienceAsset.id, id),
  });
  if (!asset) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const audio = await getObject(asset.audioObjectKey);
  const range = request.headers.get("range");
  if (range) {
    const match = /bytes=(\d+)-(\d*)/.exec(range);
    if (match) {
      const start = Number(match[1]);
      const end = match[2] ? Number(match[2]) : audio.length - 1;
      const chunk = audio.subarray(start, end + 1);
      return new NextResponse(new Uint8Array(chunk), {
        status: 206,
        headers: {
          "Content-Type": asset.contentType,
          "Content-Range": `bytes ${start}-${end}/${audio.length}`,
          "Accept-Ranges": "bytes",
          "Content-Length": String(chunk.length),
          "Cache-Control": "no-store",
        },
      });
    }
  }

  return new NextResponse(new Uint8Array(audio), {
    headers: {
      "Content-Type": asset.contentType,
      "Accept-Ranges": "bytes",
      "Content-Length": String(audio.length),
      "Cache-Control": "no-store",
    },
  });
}
