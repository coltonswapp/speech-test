import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getPlayableMp3 } from "@/lib/generate/service";
import { studioGenerateService } from "@/lib/generate/runtime";
import {
  contentDispositionAttachment,
  downloadFilename,
} from "@/lib/generate/download";
import { generateErrorResponse, requireGenerateAccess } from "@/lib/generate/http";

export async function GET(
  request: NextRequest,
  ctx: RouteContext<"/api/generate/[id]/audio">,
) {
  const denied = await requireGenerateAccess(request);
  if (denied) return denied;
  try {
    const { id } = await ctx.params;
    const { mp3, title } = await getPlayableMp3(studioGenerateService(), id);
    const download = request.nextUrl.searchParams.get("download") === "1";
    const headers = new Headers({
      "Content-Type": "audio/mpeg",
      "Content-Length": String(mp3.length),
      "Cache-Control": "private, no-store",
      "Accept-Ranges": "bytes",
    });
    if (download) {
      headers.set(
        "Content-Disposition",
        contentDispositionAttachment(downloadFilename(title, ".mp3")),
      );
    }
    return new NextResponse(new Uint8Array(mp3), { headers });
  } catch (error) {
    return generateErrorResponse(error);
  }
}
