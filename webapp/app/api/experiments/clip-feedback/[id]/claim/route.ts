import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { claimBodySchema } from "@/lib/clip-agent/schema";
import { claimAttempt } from "@/lib/clip-agent/store";
import { attemptErrorResponse, parseBody, studioRequester } from "@/lib/clip-agent/route-helpers";

const bodySchema = claimBodySchema.extend({ takeOver: z.boolean().optional() });

/**
 * An agent takes an open report: picks up the attempt Studio dispatched to it,
 * or opens one. Snapshots the clip and returns the report, clip and playbook.
 * 409 while another attempt is working (unless takeOver).
 */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clip-feedback/[id]/claim">,
) {
  const { id } = await ctx.params;
  const body = await parseBody(request, bodySchema);
  if ("response" in body) return body.response;
  try {
    const claimed = await claimAttempt({
      feedbackId: id,
      agent: body.data.agent ?? null,
      runUrl: body.data.runUrl ?? null,
      claimedBy: await studioRequester(request),
      takeOver: body.data.takeOver ?? false,
    });
    return NextResponse.json(claimed);
  } catch (error) {
    return attemptErrorResponse(error, "claim");
  }
}
