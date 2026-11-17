import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { clipErrorResponse, loadClipOr404, requestedStepModel } from "@/lib/experiments/clips/route-helpers";
import { writeClipDraft } from "@/lib/experiments/clips/store";
import { tagClip } from "@/lib/experiments/clips/tag-review";
import { withUsageRun } from "@/lib/experiments/clips/usage";

export const maxDuration = 300;

/**
 * Tag the clip for the catalog (format, topics, register, speakers, dialect,
 * series) from its title, channel and transcript. Replaces the last automatic
 * tags; hand-set tags are kept and still win.
 */
export async function POST(request: NextRequest, ctx: RouteContext<"/api/experiments/clips/[id]/tag">) {
  try {
    const { id } = await ctx.params;
    const model = await requestedStepModel(request);
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    const draft = loaded.draft;
    const startedAt = Date.now();
    const result = await tagClip(draft, model);
    const next = {
      ...draft,
      tags: {
        ...draft.tags,
        auto: {
          ...result.pick,
          ...(result.reason ? { reason: result.reason } : {}),
          ...(result.suggested.length ? { suggested: result.suggested } : {}),
          model: result.model,
          at: new Date().toISOString(),
        },
      },
    };
    const withUsage = withUsageRun(next, {
      step: "tag",
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
