import "server-only";
import { alignAudioUrl, alignerConfigured, AlignerError } from "@/lib/aligner/client";
import { SegmentationError, tokenizeJapaneseLine } from "@/lib/dialogue/gemini-tokenize";
import { validatedTokens } from "@/lib/dialogue/japanese-segmentation";
import { isKana } from "@/lib/experiments/clips/token-edits";
import { clauseChunks, mergeInflections } from "@/lib/experiments/clips/fallback-tokens";
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

/**
 * Fallback segmentation: ICU's Japanese dictionary word break (built into
 * Node), cleaned by the same validation as Gemini output (punctuation dropped,
 * colloquial んで/んだ suffixes merged). Kana tokens read as themselves; the
 * rest get no reading, so the aligner romanizes them and flags them orange.
 */
function basicWordSplit(text: string): Array<{ text: string; reading?: string }> {
  const segments = [...new Intl.Segmenter("ja", { granularity: "word" }).segment(text)]
    .map((s) => s.segment)
    .filter((s) => s.trim().length > 0);
  const tokens = validatedTokens(segments, text) ?? [];
  return mergeInflections(
    tokens.map((t) => ({ text: t.text, ...(isKana(t.text) ? { reading: t.text } : {}) }))
  );
}

type LineTokens = { tokens: Array<{ text: string; reading?: string }>; basicSplit: boolean };

/**
 * Gemini on the whole line; if it can't segment it (long, disfluent speech
 * it "corrects"), Gemini again on clause-sized chunks; the plain word split
 * only for a chunk that still fails. Each chunk is cached like a line.
 */
async function tokenizeClipLine(
  text: string,
  callbacks: Parameters<typeof tokenizeJapaneseLine>[1]
): Promise<LineTokens> {
  try {
    return { tokens: await tokenizeJapaneseLine(text, callbacks), basicSplit: false };
  } catch (error) {
    if (!(error instanceof SegmentationError)) throw error;
  }
  const chunks = clauseChunks(text);
  if (chunks.length < 2) return { tokens: basicWordSplit(text), basicSplit: true };
  const tokens: LineTokens["tokens"] = [];
  let basicSplit = false;
  for (const chunk of chunks) {
    // A chunk that is only punctuation has no tokens.
    if (!JAPANESE_CHAR.test(chunk) && !/[0-9０-９A-Za-z]/.test(chunk)) continue;
    try {
      tokens.push(...(await tokenizeJapaneseLine(chunk, callbacks)));
    } catch (error) {
      if (!(error instanceof SegmentationError)) throw error;
      tokens.push(...basicWordSplit(chunk));
      basicSplit = true;
    }
  }
  return { tokens, basicSplit };
}

/** Lines tokenized at once (each is its own Gemini request). */
const TOKENIZE_CONCURRENCY = 4;

/**
 * Tokenize every sentence that has no tokens yet (cached per line).
 * `retokenize`: sentence indexes to throw away and tokenize again (their
 * timings go too; "Align edited lines" times them without touching the rest).
 */
export async function tokenizeClipDraft(
  input: ClipDraft,
  options: { retokenize?: number[] } = {}
): Promise<ClipDraft> {
  if (input.sentences.length === 0) {
    throw new ClipPipelineError("Transcribe or enter the transcript first.", 400);
  }
  const redo = new Set(options.retokenize ?? []);
  for (const i of redo) {
    if (!Number.isInteger(i) || i < 0 || i >= input.sentences.length) {
      throw new ClipPipelineError(`No line ${i + 1}.`, 400);
    }
  }
  const draft: ClipDraft =
    redo.size === 0
      ? input
      : {
          ...input,
          sentences: input.sentences.map((s, i) =>
            redo.has(i)
              ? { ...s, tokens: null, score: undefined, flagsCleared: undefined, basicSplit: undefined }
              : s
          ),
        };
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
  // One request per line (batching lines changes how Gemini segments them),
  // but several lines in flight at once: a 37-line clip took 6.5 minutes one
  // line at a time. Each line's answer doesn't depend on the others.
  const sentences: ClipSentence[] = [...draft.sentences];
  const todo = draft.sentences.flatMap((s, i) => (s.tokens && s.tokens.length > 0 ? [] : [i]));
  lines = todo.length;
  let cursor = 0;
  const worker = async () => {
    while (cursor < todo.length) {
      const index = todo[cursor++]!;
      const sentence = draft.sentences[index]!;
      let tokens;
      let basicSplit = false;
      try {
        // Real speech is often disfluent and Gemini "fixes" it, so its tokens
        // stop matching the line; tokenizeClipLine falls back rather than
        // blocking the clip on one line.
        ({ tokens, basicSplit } = await tokenizeClipLine(sentence.text, { onUsage, onCacheHit }));
      } catch (error) {
        throw new ClipPipelineError(error instanceof Error ? error.message : String(error), 502);
      }
      if (tokens.length === 0) {
        throw new ClipPipelineError(`Could not segment “${sentence.text.slice(0, 24)}”.`, 422);
      }
      sentences[index] = {
        ...sentence,
        tokens: tokens.map((t) => ({ text: t.text, ...(t.reading ? { reading: t.reading } : {}) })),
        score: undefined,
        ...(basicSplit ? { basicSplit: true } : {}),
      };
    }
  };
  await Promise.all(Array.from({ length: Math.min(TOKENIZE_CONCURRENCY, todo.length) }, worker));
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
