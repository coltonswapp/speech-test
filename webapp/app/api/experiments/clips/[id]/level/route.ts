import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { estimateClipLevel } from "@/lib/experiments/clips/level";
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
    // Time actually spent speaking (first token to last), once aligned.
    const first = draft.sentences[0]?.tokens?.[0]?.startSec;
    const last = draft.sentences.at(-1)?.tokens?.at(-1)?.endSec;
    const spoken =
      clipIsAligned(draft) && first !== undefined && last !== undefined ? last - first : null;
    const result = await estimateClipLevel(
      draft.sentences.map((s) => s.text),
      spoken,
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
