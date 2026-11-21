import { z } from "zod";
import type { DialogueHighlights, GrammarPatternRef } from "@/lib/dialogue/types";
import { clipTokensProblem, tokenRanges } from "@/lib/experiments/clips/token-edits";
import type { ClipDraft, ClipSentence } from "@/lib/experiments/clips/types";

// Split or merge subtitle lines at token boundaries. Pure: the PATCH route
// and tests share this. Unlike applySentenceEdits, tokens, timings, alignment
// and the feed verdict stay put — the Japanese is only re-chunked.

export const CLIP_MAX_SENTENCES = 200;

/**
 * `atToken` is the first token of the next line (1…n−1), or several of those
 * in order. Punctuation between tokens stays on the left.
 */
export const clipSplitSchema = z.object({
  sentence: z.number().int().min(0),
  atToken: z.union([
    z.number().int().min(1),
    z.array(z.number().int().min(1)).min(1).max(CLIP_MAX_SENTENCES - 1),
  ]),
  /** One English string per new line. Empty string leaves that line untranslated. */
  english: z.array(z.string().max(1000)).max(CLIP_MAX_SENTENCES).optional(),
});
export type ClipSplit = z.infer<typeof clipSplitSchema>;

/** Join `sentence` with the following `count` lines (default 1). */
export const clipMergeSchema = z.object({
  sentence: z.number().int().min(0),
  count: z.number().int().min(1).max(CLIP_MAX_SENTENCES - 1).optional(),
  /** English for the joined line. Empty string clears it. Omit to join existing English. */
  english: z.string().max(1000).optional(),
});
export type ClipMerge = z.infer<typeof clipMergeSchema>;

export type ClipEditResult = { draft: ClipDraft } | { error: string };

function sentenceMissing(index: number): string {
  return `No sentence ${index + 1}.`;
}

function cutsFrom(atToken: ClipSplit["atToken"], tokenCount: number): number[] | { error: string } {
  const raw = (Array.isArray(atToken) ? atToken : [atToken]).map((n) => Math.trunc(n));
  const cuts = [...new Set(raw)].sort((a, b) => a - b);
  if (cuts.some((c) => c < 1 || c >= tokenCount)) {
    return { error: `atToken must be a token index to start the next line at (1...${tokenCount - 1}).` };
  }
  if (cuts.length === 0) return { error: "atToken must fall inside the line." };
  return cuts;
}

function assignEnglish(pieces: ClipSentence[], english: string[] | undefined): ClipSentence[] | { error: string } {
  if (!english) return pieces;
  if (english.length !== pieces.length) {
    return { error: `English must have one string per new line (${pieces.length}).` };
  }
  return pieces.map((piece, i) => {
    const en = english[i]!.trim();
    if (!en) {
      if (!piece.en) return piece;
      const next = { ...piece };
      delete next.en;
      return next;
    }
    return { ...piece, en };
  });
}

function copyLineMeta(sentence: ClipSentence, text: string, tokens: NonNullable<ClipSentence["tokens"]>): ClipSentence {
  return {
    text,
    tokens,
    ...(sentence.score !== undefined ? { score: sentence.score } : {}),
    ...(sentence.flagsCleared ? { flagsCleared: true } : {}),
    ...(sentence.basicSplit ? { basicSplit: true } : {}),
  };
}

function remapHighlights(
  highlights: DialogueHighlights | undefined,
  mapRange: (start: number, end: number) => { start: number; end: number }
): DialogueHighlights | undefined {
  if (!highlights?.grammarPatterns?.length) return highlights;
  const grammarPatterns = highlights.grammarPatterns.map((pattern): GrammarPatternRef => {
    if (pattern.sourceSpokenStart === undefined) return pattern;
    const start = pattern.sourceSpokenStart;
    const end = pattern.sourceSpokenEnd ?? start;
    const mapped = mapRange(start, end);
    const next: GrammarPatternRef = { ...pattern, sourceSpokenStart: mapped.start };
    if (mapped.end !== mapped.start) next.sourceSpokenEnd = mapped.end;
    else delete next.sourceSpokenEnd;
    return next;
  });
  return { ...highlights, grammarPatterns };
}

/**
 * Break one line into several at token boundaries. Each piece keeps its
 * tokens (text, reading, timing); line start/end are the first and last
 * token. Alignment and feed on the draft are left alone.
 */
export function applyClipSplit(draft: ClipDraft, input: ClipSplit): ClipEditResult {
  const index = input.sentence;
  const sentence = draft.sentences[index];
  if (!sentence) return { error: sentenceMissing(index) };
  const tokens = sentence.tokens;
  if (!tokens || tokens.length < 2) {
    return { error: "Need at least two tokens to split a line." };
  }
  const cuts = cutsFrom(input.atToken, tokens.length);
  if ("error" in cuts) return cuts;
  const ranges = tokenRanges(sentence.text, tokens);
  if (!ranges) {
    return { error: clipTokensProblem(sentence.text, tokens) ?? "Tokens must spell out the sentence in order, skipping only punctuation and spaces." };
  }

  const bounds = [0, ...cuts, tokens.length];
  const pieces: ClipSentence[] = [];
  for (let i = 0; i < bounds.length - 1; i++) {
    const from = bounds[i]!;
    const to = bounds[i + 1]!;
    const charStart = from === 0 ? 0 : ranges[from]!.start;
    const charEnd = to === tokens.length ? sentence.text.length : ranges[to]!.start;
    const text = sentence.text.slice(charStart, charEnd);
    const pieceTokens = tokens.slice(from, to);
    if (pieceTokens.length === 0) {
      return { error: "Each new line needs at least one token." };
    }
    const problem = clipTokensProblem(text, pieceTokens);
    if (problem) return { error: problem };
    pieces.push(copyLineMeta(sentence, text, pieceTokens));
  }
  if (pieces.map((p) => p.text).join("") !== sentence.text) {
    return { error: "Split pieces must join back to the original sentence." };
  }
  const withEnglish = assignEnglish(pieces, input.english);
  if ("error" in withEnglish) return withEnglish;
  if (draft.sentences.length - 1 + withEnglish.length > CLIP_MAX_SENTENCES) {
    return { error: `A clip can have at most ${CLIP_MAX_SENTENCES} sentences.` };
  }

  const added = withEnglish.length - 1;
  const sentences = [
    ...draft.sentences.slice(0, index),
    ...withEnglish,
    ...draft.sentences.slice(index + 1),
  ];
  const highlights = remapHighlights(draft.highlights, (start, end) => ({
    start: start <= index ? start : start + added,
    end: end < index ? end : end + added,
  }));
  return {
    draft: {
      ...draft,
      sentences,
      ...(highlights !== undefined ? { highlights } : {}),
    },
  };
}

/**
 * Join adjacent lines. Tokens concatenate; timings stay. Alignment and feed
 * are left alone. Pieces must join to the original texts with no extra glue.
 */
export function applyClipMerge(draft: ClipDraft, input: ClipMerge): ClipEditResult {
  const index = input.sentence;
  const count = input.count ?? 1;
  if (!draft.sentences[index]) return { error: sentenceMissing(index) };
  const last = index + count;
  if (!draft.sentences[last]) {
    return { error: `No sentence ${last + 1} to merge with sentence ${index + 1}.` };
  }
  const group = draft.sentences.slice(index, last + 1);
  if (group.some((s) => !s.tokens || s.tokens.length === 0)) {
    return { error: "Every line being merged needs tokens." };
  }
  const text = group.map((s) => s.text).join("");
  const tokens = group.flatMap((s) => s.tokens ?? []);
  const problem = clipTokensProblem(text, tokens);
  if (problem) return { error: problem };

  const scores = group.map((s) => s.score).filter((n): n is number => n !== undefined);
  const merged: ClipSentence = {
    text,
    tokens,
    ...(scores.length === group.length ? { score: Math.min(...scores) } : {}),
    ...(group.every((s) => s.flagsCleared) ? { flagsCleared: true } : {}),
    ...(group.some((s) => s.basicSplit) ? { basicSplit: true } : {}),
  };
  if (input.english !== undefined) {
    const en = input.english.trim();
    if (en) merged.en = en;
  } else {
    const english = group.map((s) => s.en?.trim() ?? "");
    if (english.every(Boolean)) merged.en = english.join(" ");
  }

  const sentences = [
    ...draft.sentences.slice(0, index),
    merged,
    ...draft.sentences.slice(last + 1),
  ];
  const highlights = remapHighlights(draft.highlights, (start, end) => ({
    start: start < index ? start : start <= last ? index : start - count,
    end: end < index ? end : end <= last ? index : end - count,
  }));
  return {
    draft: {
      ...draft,
      sentences,
      ...(highlights !== undefined ? { highlights } : {}),
    },
  };
}
