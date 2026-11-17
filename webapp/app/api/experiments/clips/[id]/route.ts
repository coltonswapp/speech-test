import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { clipTagPickSchema } from "@/lib/experiments/clips/tags";
import { highlightsSchema } from "@/lib/dialogue/types";
import { clipErrorResponse, loadClipOr404 } from "@/lib/experiments/clips/route-helpers";
import { clipAudioUrl, deleteClip, writeClipDraft } from "@/lib/experiments/clips/store";
import {
  applySentenceEdits,
  clipJlptLevelSchema,
  clipOrientationSchema,
  type ClipDraftResponse,
} from "@/lib/experiments/clips/types";
import { carryTimings, clipTokensProblem } from "@/lib/experiments/clips/token-edits";
import { normalizeReading } from "@/lib/dialogue/token-readings";

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]">
) {
  try {
    const { id } = await ctx.params;
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    const body: ClipDraftResponse = {
      draft: loaded.draft,
      audioUrl: await clipAudioUrl(id),
    };
    return NextResponse.json(body, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return clipErrorResponse(error);
  }
}

/**
 * Deletes the clip (draft + audio) so the id can be reused, e.g. after a bad
 * cut. Anything saved from it in the app stops resolving; for a clip that has
 * been live, PATCH `deprecated` instead.
 */
export async function DELETE(
  _request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]">
) {
  try {
    const { id } = await ctx.params;
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    await deleteClip(id);
    return NextResponse.json({ ok: true });
  } catch (error) {
    return clipErrorResponse(error);
  }
}

const patchSchema = z.object({
  /** Full transcript, one sentence per entry. */
  sentences: z.array(z.string()).max(200).optional(),
  shiftSec: z.number().min(-2).max(2).optional(),
  /** Portrait = 9:16 Short (taller player in the app). */
  orientation: clipOrientationSchema.optional(),
  /** English per sentence, same order and length as the saved transcript. */
  english: z.array(z.string().max(1000)).max(200).optional(),
  /**
   * Hand-edited tokens for one sentence (split / merge / reading). Drops that
   * sentence's timings, so the clip needs re-aligning.
   */
  tokens: z
    .object({
      sentence: z.number().int().min(0),
      tokens: z
        .array(z.object({ text: z.string().min(1).max(100), reading: z.string().max(100).optional() }))
        .min(1)
        .max(300),
    })
    .optional(),
  /** Marks one sentence's warnings as reviewed (or un-marks it). */
  clearFlags: z.object({ sentence: z.number().int().min(0), cleared: z.boolean() }).optional(),
  /** Replaces highlights; null clears them. */
  highlights: highlightsSchema.nullable().optional(),
  /** Hand-set level (5 = N5 … 1 = N1); null clears the rating. */
  jlptLevel: clipJlptLevelSchema.nullable().optional(),
  /** Hand-set feed answer: true = always in the feed, false = never; null = back to the automatic verdict. */
  feedEligible: z.boolean().nullable().optional(),
  /** Hand-set catalog tags (vocabulary in tags.ts); null = back to the Tag step's. */
  tags: clipTagPickSchema.nullable().optional(),
  /** Retire the clip (optional reason), or null to restore it. */
  deprecated: z.object({ reason: z.string().max(200).optional() }).nullable().optional(),
});

export async function PATCH(
  request: NextRequest,
  ctx: RouteContext<"/api/experiments/clips/[id]">
) {
  try {
    const { id } = await ctx.params;
    const parsed = patchSchema.safeParse(await request.json().catch(() => null));
    if (!parsed.success) {
      return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
    }
    const loaded = await loadClipOr404(id);
    if ("response" in loaded) return loaded.response;
    let draft = loaded.draft;
    if (parsed.data.sentences) {
      const sentences = applySentenceEdits(draft, parsed.data.sentences);
      if (sentences !== draft.sentences) {
        // The Feed step judged the old transcript; a hand-set answer stays.
        const feed = draft.feed?.manual ? { manual: draft.feed.manual } : undefined;
        draft = { ...draft, sentences, alignment: undefined, feed };
      }
    }
    if (parsed.data.english) {
      const english = parsed.data.english;
      if (english.length !== draft.sentences.length) {
        return NextResponse.json(
          { error: "English lines must match the saved transcript. Save the transcript first." },
          { status: 400 }
        );
      }
      draft = {
        ...draft,
        sentences: draft.sentences.map((sentence, i) => {
          const en = english[i].trim();
          const next = { ...sentence };
          if (en) next.en = en;
          else delete next.en;
          return next;
        }),
      };
    }
    if (parsed.data.tokens) {
      const { sentence: index, tokens } = parsed.data.tokens;
      const sentence = draft.sentences[index];
      if (!sentence) {
        return NextResponse.json({ error: `No sentence ${index + 1}.` }, { status: 400 });
      }
      const problem = clipTokensProblem(sentence.text, tokens);
      if (problem) return NextResponse.json({ error: problem }, { status: 400 });
      const cleaned = tokens.map((token) => {
        const reading = normalizeReading(token.reading);
        return { text: token.text, ...(reading ? { reading } : {}) };
      });
      // Merges and reading fixes keep their times; only split halves need aligning.
      const carried = carryTimings(sentence.text, sentence.tokens ?? [], cleaned);
      const stillTimed = carried.every((t) => t.startSec !== undefined && t.endSec !== undefined);
      draft = {
        ...draft,
        sentences: draft.sentences.map((s, i) =>
          i !== index
            ? s
            : stillTimed
              ? { ...s, tokens: carried, basicSplit: undefined }
              : {
                  ...s,
                  tokens: carried,
                  score: undefined,
                  flagsCleared: undefined,
                  basicSplit: undefined,
                }
        ),
        ...(stillTimed ? {} : { alignment: undefined }),
      };
    }
    if (parsed.data.clearFlags) {
      const { sentence: index, cleared } = parsed.data.clearFlags;
      if (!draft.sentences[index]) {
        return NextResponse.json({ error: `No sentence ${index + 1}.` }, { status: 400 });
      }
      draft = {
        ...draft,
        sentences: draft.sentences.map((s, i) => {
          if (i !== index) return s;
          const next = { ...s };
          if (cleared) next.flagsCleared = true;
          else delete next.flagsCleared;
          return next;
        }),
      };
    }
    if (parsed.data.highlights !== undefined) {
      const highlights = parsed.data.highlights;
      draft = { ...draft, highlights: highlights ?? undefined };
    }
    if (parsed.data.jlptLevel !== undefined) {
      const jlptLevel = parsed.data.jlptLevel;
      draft = {
        ...draft,
        difficulty:
          jlptLevel === null
            ? undefined
            : { jlptLevel, source: "manual", at: new Date().toISOString() },
      };
    }
    if (parsed.data.feedEligible !== undefined) {
      const eligible = parsed.data.feedEligible;
      const auto = draft.feed?.auto;
      const feed = {
        ...(auto ? { auto } : {}),
        ...(eligible === null ? {} : { manual: { eligible, at: new Date().toISOString() } }),
      };
      draft = { ...draft, feed: feed.auto || feed.manual ? feed : undefined };
    }
    if (parsed.data.tags !== undefined) {
      const manual = parsed.data.tags;
      const auto = draft.tags?.auto;
      const tags = {
        ...(auto ? { auto } : {}),
        ...(manual === null ? {} : { manual: { ...manual, at: new Date().toISOString() } }),
      };
      draft = { ...draft, tags: tags.auto || tags.manual ? tags : undefined };
    }
    if (parsed.data.deprecated !== undefined) {
      const reason = parsed.data.deprecated?.reason?.trim();
      draft = {
        ...draft,
        deprecated:
          parsed.data.deprecated === null
            ? undefined
            : // Re-deprecating keeps the original date; only the reason changes.
              { at: draft.deprecated?.at ?? new Date().toISOString(), ...(reason ? { reason } : {}) },
      };
    }
    if (parsed.data.shiftSec !== undefined) {
      draft = { ...draft, shiftSec: Math.round(parsed.data.shiftSec * 1000) / 1000 };
    }
    if (parsed.data.orientation !== undefined) {
      draft = { ...draft, orientation: parsed.data.orientation };
    }
    return NextResponse.json({ draft: await writeClipDraft(draft) });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
