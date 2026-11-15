import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { clipFeedNotReady, clipFeedRules } from "@/lib/experiments/clips/feed";
import { reviewClipForFeed } from "@/lib/experiments/clips/feed-review";
import { ClipPipelineError } from "@/lib/experiments/clips/asr";
import { clipErrorResponse, loadClipOr404, requestedStepModel } from "@/lib/experiments/clips/route-helpers";
import { writeClipDraft } from "@/lib/experiments/clips/store";
import { withUsageRun } from "@/lib/experiments/clips/usage";

export const maxDuration = 300;

/**
 * Decide whether the clip belongs in the app's feed (replaces the last
 * automatic verdict; a hand-set answer is kept and still wins). A clip that
 * fails the measured rules is turned down without asking the model.
 */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]/feed">
) {
  try {
    const { id } = await ctx.params;
    const model = await requestedStepModel(request);
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    const draft = loaded.draft;
    const notReady = clipFeedNotReady(draft);
    if (notReady) {
      throw new ClipPipelineError(`${notReady} Align and translate the clip first.`, 400);
    }
    const at = new Date().toISOString();
    const failed = clipFeedRules(draft).filter((rule) => !rule.ok);
    if (failed.length > 0) {
      const next = {
        ...draft,
        feed: {
          ...draft.feed,
          auto: { eligible: false, reason: failed.map((rule) => rule.problem).join(" "), at },
        },
      };
      return NextResponse.json({ draft: await writeClipDraft(next) });
    }
    const startedAt = Date.now();
    const result = await reviewClipForFeed(draft, model);
    const next = {
      ...draft,
      feed: {
        ...draft.feed,
        auto: {
          eligible: result.suitable,
          ...(result.reason ? { reason: result.reason } : {}),
          model: result.model,
          at,
        },
      },
    };
    const withUsage = withUsageRun(next, {
      step: "feed",
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
