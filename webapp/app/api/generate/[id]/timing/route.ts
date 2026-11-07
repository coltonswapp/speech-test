import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { requireGeneration, timingDownloadPayload } from "@/lib/generate/service";
import { studioGenerateService } from "@/lib/generate/runtime";
import { generateErrorResponse } from "@/lib/generate/http";

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/generate/[id]/timing">,
) {
  try {
    const { id } = await ctx.params;
    const row = await requireGeneration(studioGenerateService(), id);
    const payload = timingDownloadPayload(row);
    const safeName = `${row.title.replace(/[^\p{L}\p{N}\-_ ]+/gu, "").trim() || "timing"}.json`;
    return new NextResponse(JSON.stringify(payload, null, 2), {
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Content-Disposition": `attachment; filename="${safeName}"`,
        "Cache-Control": "private, no-store",
      },
    });
  } catch (error) {
    return generateErrorResponse(error);
  }
}
