import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { dispatchBodySchema } from "@/lib/clip-agent/schema";
import { dispatchAttempt } from "@/lib/clip-agent/store";
import { attemptErrorResponse, parseBody, studioRequester } from "@/lib/clip-agent/route-helpers";

/**
 * Studio "Send to agent": opens an attempt on an open report and posts the
 * target's webhook. 409 when the report already has a dispatched or working
 * attempt. A failed delivery still returns the attempt (status failed).
 */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clip-feedback/[id]/dispatch">,
) {
  const { id } = await ctx.params;
  const body = await parseBody(request, dispatchBodySchema);
  if ("response" in body) return body.response;
  try {
    const attempt = await dispatchAttempt({
      feedbackId: id,
      agent: body.data.agent,
      instructions: body.data.instructions || null,
      dispatchedBy: await studioRequester(request),
    });
    return NextResponse.json({ attempt });
  } catch (error) {
    return attemptErrorResponse(error, "dispatch");
  }
}
