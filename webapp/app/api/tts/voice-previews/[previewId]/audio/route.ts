import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { voicePreview } from "@/lib/db/schema";
import { getObject } from "@/lib/storage/r2";

export async function GET(
  request: NextRequest,
  ctx: RouteContext<"/api/tts/voice-previews/[previewId]/audio">
) {
  const { previewId } = await ctx.params;

  const preview = await db.query.voicePreview.findFirst({
    where: eq(voicePreview.id, previewId),
  });
  if (!preview) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const wav = await getObject(preview.audioObjectKey);

  const range = request.headers.get("range");
  if (range) {
    const match = /bytes=(\d+)-(\d*)/.exec(range);
    if (match) {
      const start = Number(match[1]);
      const end = match[2] ? Number(match[2]) : wav.length - 1;
      const chunk = wav.subarray(start, end + 1);
      return new NextResponse(new Uint8Array(chunk), {
        status: 206,
        headers: {
          "Content-Type": "audio/wav",
          "Content-Range": `bytes ${start}-${end}/${wav.length}`,
          "Accept-Ranges": "bytes",
          "Content-Length": String(chunk.length),
        },
      });
    }
  }

  return new NextResponse(new Uint8Array(wav), {
    headers: {
      "Content-Type": "audio/wav",
      "Accept-Ranges": "bytes",
      "Content-Length": String(wav.length),
    },
  });
}
