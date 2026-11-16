import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { clipSpeechPace, estimateClipLevel } from "@/lib/experiments/clips/level";
import { clipErrorResponse, loadClipOr404, requestedStepModel } from "@/lib/experiments/clips/route-helpers";
import { writeClipDraft } from "@/lib/experiments/clips/store";
import { clipIsAligned } from "@/lib/experiments/clips/types";
import { withUsageRun } from "@/lib/experiments/clips/usage";

export const maxDuration = 300;

/** Estimate the clip's JLPT level from its transcript (replaces the current level). */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]/level">
) {
  try {
    const { id } = await ctx.params;
    const model = await requestedStepModel(request);
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    const draft = loaded.draft;
    const startedAt = Date.now();
    // Speaking pace (characters per second inside lines), once aligned.
    const pace = clipIsAligned(draft) ? clipSpeechPace(draft.sentences) : null;
    const result = await estimateClipLevel(
      draft.sentences.map((s) => s.text),
      pace,
      model
    );
    const at = new Date().toISOString();
    const next = {
      ...draft,
      difficulty: {
        jlptLevel: result.jlptLevel,
        source: "auto" as const,
        ...(result.reason ? { reason: result.reason } : {}),
        model: result.model,
        at,
      },
    };
    const withUsage = withUsageRun(next, {
      step: "level",
      model: result.model,
      startedAt,
      calls: 1,
      tokens: result.tokens,
      lines: draft.sentences.length,
    });
    return NextResponse.json({ draft: await writeClipDraft(withUsage) });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
