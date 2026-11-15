import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getObject } from "@/lib/storage/r2";
import { transcribeClipAudio } from "@/lib/experiments/clips/asr";
import { clipErrorResponse, loadClipOr404, requestedStepModel } from "@/lib/experiments/clips/route-helpers";
import { clipAudioKey, writeClipDraft } from "@/lib/experiments/clips/store";
import { withUsageRun } from "@/lib/experiments/clips/usage";

export const maxDuration = 300;

/** Run Gemini ASR on clip.wav and replace the transcript (clears tokens and timings). */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]/transcribe">
) {
  try {
    const { id } = await ctx.params;
    const model = await requestedStepModel(request);
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    const startedAt = Date.now();
    const wav = await getObject(clipAudioKey(id));
    const asr = await transcribeClipAudio(wav, model);
    const next = {
      ...loaded.draft,
      sentences: asr.sentences.map((text) => ({ text, tokens: null })),
      asr: { model: asr.model, at: new Date().toISOString() },
      alignment: undefined,
      // The Feed step judged the old transcript; a hand-set answer stays.
      feed: loaded.draft.feed?.manual ? { manual: loaded.draft.feed.manual } : undefined,
    };
    const withUsage = withUsageRun(next, {
      step: "transcribe",
      model: asr.model,
      startedAt,
      calls: 1,
      tokens: asr.tokens,
      lines: asr.sentences.length,
    });
    return NextResponse.json({ draft: await writeClipDraft(withUsage) });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
