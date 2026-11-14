import "server-only";
import { alignAudioUrl, alignerConfigured, AlignerError } from "@/lib/aligner/client";
import { tokenizeJapaneseLine } from "@/lib/dialogue/gemini-tokenize";
import { ClipPipelineError } from "@/lib/experiments/clips/asr";
import { clipAudioUrl } from "@/lib/experiments/clips/store";
import {
  sentenceIsTimed,
  type ClipDraft,
  type ClipSentence,
  type GeminiTokenCounts,
} from "@/lib/experiments/clips/types";
import { geminiTokenizeModel } from "@/lib/gemini/text-model";
import { addTokenCounts, withUsageRun, ZERO_TOKENS } from "@/lib/experiments/clips/usage";

const round3 = (n: number) => Math.round(n * 1000) / 1000;

/** Hiragana, katakana (incl. ー) or kanji. */
const JAPANESE_CHAR = /[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}ー]/u;

/** Tokenize every sentence that has no tokens yet (cached per line). */
export async function tokenizeClipDraft(draft: ClipDraft): Promise<ClipDraft> {
  if (draft.sentences.length === 0) {
    throw new ClipPipelineError("Transcribe or enter the transcript first.", 400);
  }
  const startedAt = Date.now();
  let calls = 0;
  let cachedLines = 0;
  let lines = 0;
  let tokensSpent: GeminiTokenCounts = ZERO_TOKENS;
  const onUsage = (usage: { promptTokens: number; outputTokens: number }) => {
    calls += 1;
    // The shared tokenizer reports output with thinking folded in.
    tokensSpent = addTokenCounts(tokensSpent, {
      inputTokens: usage.promptTokens,
      audioInputTokens: 0,
      outputTokens: usage.outputTokens,
      thinkingTokens: 0,
    });
  };
  const onCacheHit = () => {
    cachedLines += 1;
  };
  // Lines with no kana or kanji (ASR sometimes writes English as English)
  // can't be segmented or aligned; say which one and how to fix it.
  const latinOnly = draft.sentences.findIndex((s) => !JAPANESE_CHAR.test(s.text));
  if (latinOnly >= 0) {
    const text = draft.sentences[latinOnly].text;
    throw new ClipPipelineError(
      `Line ${latinOnly + 1} (“${text.slice(0, 40)}”) has no Japanese. Write it in katakana as a subtitle would (e.g. Let's go! → レッツゴー！) or delete it, save, then tokenize.`,
      422
    );
  }
  const sentences: ClipSentence[] = [];
  for (const sentence of draft.sentences) {
    if (sentence.tokens && sentence.tokens.length > 0) {
      sentences.push(sentence);
      continue;
    }
    let tokens;
    try {
      lines += 1;
      tokens = await tokenizeJapaneseLine(sentence.text, { onUsage, onCacheHit });
    } catch (error) {
      throw new ClipPipelineError(
        error instanceof Error ? error.message : String(error),
        502
      );
    }
    if (tokens.length === 0) {
      throw new ClipPipelineError(`Could not segment “${sentence.text.slice(0, 24)}”.`, 422);
    }
    sentences.push({
      ...sentence,
      tokens: tokens.map((t) => ({ text: t.text, ...(t.reading ? { reading: t.reading } : {}) })),
      score: undefined,
    });
  }
  const next = { ...draft, sentences, alignment: undefined };
  if (lines === 0) return next; // nothing needed tokenizing; don't log an empty run
  return withUsageRun(
    next,
    {
      step: "tokenize",
      model: geminiTokenizeModel(),
      startedAt,
      calls,
      tokens: tokensSpent,
      cachedLines,
      lines,
    }
  );
}

/**
 * Force-align the whole transcript to clip.wav in one aligner call. Times are
 * stored clip-relative; the aligner does not chunk, so clips are capped at
 * CLIP_MAX_SECONDS.
 *
 * `onlyUntimed`: still one whole-clip call (the aligner needs the full script
 * to place a line), but only lines missing timings take the new result. Timed
 * lines, their scores and their reviewed flags stay exactly as they were. New
 * times are clamped between the neighbouring kept lines so they can't overlap.
 */
export async function alignClipDraft(
  draft: ClipDraft,
  options: { onlyUntimed?: boolean } = {}
): Promise<ClipDraft> {
  if (!alignerConfigured()) {
    throw new ClipPipelineError("ALIGNER_URL / ALIGNER_TOKEN are not set.", 503);
  }
  if (!draft.sentences.every((s) => s.tokens && s.tokens.length > 0)) {
    throw new ClipPipelineError("Tokenize the transcript before aligning.", 400);
  }
  const keep = draft.sentences.map((s) => Boolean(options.onlyUntimed) && sentenceIsTimed(s));
  if (options.onlyUntimed && keep.every(Boolean)) {
    throw new ClipPipelineError("Every line already has timings.", 400);
  }
  const startedAt = Date.now();
  const audioUrl = await clipAudioUrl(draft.id, 10 * 60);
  let result;
  try {
    result = await alignAudioUrl({
      audioUrl,
      lines: draft.sentences.map((s) => ({
        text: s.text,
        tokens: (s.tokens ?? []).map((t) => ({ text: t.text, reading: t.reading })),
      })),
    });
  } catch (error) {
    if (error instanceof AlignerError) {
      throw new ClipPipelineError(error.message, error.status === 422 ? 422 : 502);
    }
    throw error;
  }

  // Bounds for re-timed lines: end of the previous kept line, start of the next.
  const keptEnd = (i: number) => {
    for (let k = i - 1; k >= 0; k--) {
      if (keep[k]) return draft.sentences[k].tokens?.at(-1)?.endSec ?? 0;
    }
    return 0;
  };
  const keptStart = (i: number) => {
    for (let k = i + 1; k < draft.sentences.length; k++) {
      if (keep[k]) return draft.sentences[k].tokens?.[0]?.startSec ?? Infinity;
    }
    return Infinity;
  };

  const sentences = draft.sentences.map((sentence, i): ClipSentence => {
    if (keep[i]) return sentence;
    const line = result.lines[i];
    const lo = keptEnd(i);
    const hi = Math.max(lo, keptStart(i));
    const clamp = (t: number) => Math.min(hi, Math.max(lo, t));
    return {
      text: sentence.text,
      ...(sentence.en ? { en: sentence.en } : {}),
      score: round3(line.score),
      tokens: (sentence.tokens ?? []).map((token, j) => {
        const timed = line.tokens[j];
        return {
          text: token.text,
          ...(token.reading ? { reading: token.reading } : {}),
          startSec: round3(clamp(timed.startSeconds)),
          endSec: round3(clamp(timed.endSeconds)),
          score: round3(timed.score),
          readingFallback: timed.readingFallback,
        };
      }),
    };
  });
  return withUsageRun(
    {
      ...draft,
      sentences,
      alignment: { alignerVersion: result.alignerVersion, at: new Date().toISOString() },
    },
    {
      step: "align",
      model: result.alignerVersion,
      startedAt,
      calls: 0,
      lines: keep.filter((k) => !k).length,
    }
  );
}
