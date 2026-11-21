import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { finishBodySchema } from "@/lib/clip-agent/schema";
import { finishAttempt } from "@/lib/clip-agent/store";
import { attemptErrorResponse, parseBody } from "@/lib/clip-agent/route-helpers";

/**
 * Closes a working attempt with {outcome, summary}. Snapshots the clip again;
 * fixed / no_change_needed also resolve the report. Returns the attempt with
 * its diff.
 */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clip-agent-attempts/[id]/finish">,
) {
  const { id } = await ctx.params;
  const body = await parseBody(request, finishBodySchema);
  if ("response" in body) return body.response;
  try {
    return NextResponse.json(await finishAttempt({ attemptId: id, ...body.data }));
  } catch (error) {
    return attemptErrorResponse(error, "finish");
  }
}
