import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { translateClipSentences } from "@/lib/experiments/clips/translate";
import { clipErrorResponse, loadClipOr404, requestedStepModel } from "@/lib/experiments/clips/route-helpers";
import { writeClipDraft } from "@/lib/experiments/clips/store";
import { withUsageRun } from "@/lib/experiments/clips/usage";

export const maxDuration = 300;

/** Translate every sentence to English in one call (replaces existing English). */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]/translate">
) {
  try {
    const { id } = await ctx.params;
    const model = await requestedStepModel(request);
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    const draft = loaded.draft;
    const startedAt = Date.now();
    const result = await translateClipSentences(
      draft.sentences.map((s) => s.text),
      model
    );
    const next = {
      ...draft,
      sentences: draft.sentences.map((sentence, i) => ({ ...sentence, en: result.translations[i] })),
      translation: { model: result.model, at: new Date().toISOString() },
    };
    const withUsage = withUsageRun(next, {
      step: "translate",
      model: result.model,
      startedAt,
      calls: result.calls,
      tokens: result.tokens,
      lines: draft.sentences.length,
    });
    return NextResponse.json({ draft: await writeClipDraft(withUsage) });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
