import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { requireReadyGeneration, timingDownloadPayload } from "@/lib/generate/service";
import { studioGenerateService } from "@/lib/generate/runtime";
import {
  contentDispositionAttachment,
  downloadFilename,
} from "@/lib/generate/download";
import { generateErrorResponse, rejectLearnerQaAccess } from "@/lib/generate/http";

export async function GET(
  request: NextRequest,
  ctx: RouteContext<"/api/generate/[id]/timing">,
) {
  const forbidden = rejectLearnerQaAccess(request);
  if (forbidden) return forbidden;
  try {
    const { id } = await ctx.params;
    const row = await requireReadyGeneration(studioGenerateService(), id);
    const payload = timingDownloadPayload(row);
    const headers = new Headers({
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "private, no-store",
    });
    headers.set(
      "Content-Disposition",
      contentDispositionAttachment(downloadFilename(row.title, ".json")),
    );
    return new NextResponse(JSON.stringify(payload, null, 2), { headers });
  } catch (error) {
    return generateErrorResponse(error);
  }
}
