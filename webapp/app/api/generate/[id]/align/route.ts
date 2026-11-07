import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { alignGeneration, publicGeneration } from "@/lib/generate/service";
import { generateAlignRequestSchema } from "@/lib/generate/types";
import { studioGenerateService } from "@/lib/generate/runtime";
import { generateErrorResponse, rejectLearnerQaAccess } from "@/lib/generate/http";

export const maxDuration = 300;

export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/generate/[id]/align">,
) {
  const forbidden = rejectLearnerQaAccess(request);
  if (forbidden) return forbidden;
  const body = await request.json().catch(() => ({}));
  const parsed = generateAlignRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  try {
    const { id } = await ctx.params;
    const row = await alignGeneration(
      studioGenerateService(),
      id,
      parsed.data.transcript,
    );
    return NextResponse.json({ generation: publicGeneration(row) });
  } catch (error) {
    return generateErrorResponse(error);
  }
}
