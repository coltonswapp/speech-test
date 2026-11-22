import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { CLIP_STEP_MODELS } from "@/lib/gemini/models";
import { transcribeClipAudio } from "@/lib/experiments/clips/asr";
import { bareTranscript, transcriptDifferences } from "@/lib/experiments/clips/asr-compare";
import { clipErrorResponse, loadClipOr404 } from "@/lib/experiments/clips/route-helpers";
import { readClipAudio, writeClipDraft } from "@/lib/experiments/clips/store";
import { withUsageRun } from "@/lib/experiments/clips/usage";
import type { GeminiTokenCounts } from "@/lib/experiments/clips/types";

// Gemini Pro can take over a minute on a 2-minute clip; models run in parallel.
export const maxDuration = 300;

const MODEL_IDS = CLIP_STEP_MODELS.map((m) => m.id) as [string, ...string[]];
const bodySchema = z.object({
  models: z.array(z.enum(MODEL_IDS)).min(1).max(4).default(["gemini-3.1-pro-preview", "gemini-3.8-flash"]),
});

/**
 * Re-transcribes the clip's stored audio with each model and shows where each
 * differs from the saved transcript. Does not change the transcript. Each
 * model's Gemini usage is appended to the clip (step "asr") so issue attempts
 * can total it. For agents without the local `pnpm clip:asr-compare`.
 */
export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]/asr-compare">,
) {
  try {
    const { id } = await ctx.params;
    const parsed = bodySchema.safeParse(await request.json().catch(() => ({})));
    if (!parsed.success) {
      return NextResponse.json(
        { error: `models: pick from ${MODEL_IDS.join(", ")}` },
        { status: 400 },
      );
    }
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    const wav = await readClipAudio(id);
    if (!wav) return NextResponse.json({ error: "The clip has no audio." }, { status: 404 });

    const saved = loaded.draft.sentences.map((s) => s.text);
    const savedBare = bareTranscript(saved);
    const models = await Promise.all(
      [...new Set(parsed.data.models)].map(async (model) => {
        const started = Date.now();
        try {
          const { sentences, tokens } = await transcribeClipAudio(wav, model);
          return {
            model,
            seconds: (Date.now() - started) / 1000,
            lines: sentences,
            /** saved → this model; `[x → ∅]` = this model didn't hear x, `[∅ → y]` = the saved transcript lacks y. */
            vsSaved: transcriptDifferences(savedBare, bareTranscript(sentences)),
            error: null as string | null,
            tokens,
          };
        } catch (error) {
          return {
            model,
            seconds: (Date.now() - started) / 1000,
            lines: [] as string[],
            vsSaved: [] as string[],
            error: error instanceof Error ? error.message : String(error),
            tokens: null as GeminiTokenCounts | null,
          };
        }
      }),
    );
    const billed = models.flatMap((row) => (row.tokens ? [{ ...row, tokens: row.tokens }] : []));
    if (billed.length > 0) {
      let draft = loaded.draft;
      for (const row of billed) {
        draft = withUsageRun(draft, {
          step: "asr",
          model: row.model,
          startedAt: Date.now() - Math.round(row.seconds * 1000),
          calls: 1,
          tokens: row.tokens,
          lines: row.lines.length,
        });
      }
      try {
        await writeClipDraft(draft);
      } catch (error) {
        console.warn("[asr-compare] could not record usage", error);
      }
    }
    return NextResponse.json({
      id,
      durationSec: loaded.draft.durationSec,
      savedBy: loaded.draft.asr?.model ?? "hand",
      saved,
      models: models.map((row) => ({
        model: row.model,
        seconds: row.seconds,
        lines: row.lines,
        vsSaved: row.vsSaved,
        error: row.error,
      })),
    });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
