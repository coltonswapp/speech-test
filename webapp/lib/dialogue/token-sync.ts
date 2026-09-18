import { isAllPunctuationOrWhitespace } from "@/lib/dialogue/japanese-segmentation";
import {
  publishedTokenSyncSchema,
  variantTokenSyncSchema,
  type PublishedTokenSync,
  type VariantTokenSync,
} from "@/lib/dialogue/types";
import { wallDelayToMediaSeconds } from "@/lib/tts/media-timing";

export const TOKEN_SYNC_VERSION = 1 as const;
/**
 * Wall-clock tap lag assumed at 1×; convert with wallDelayToMediaSeconds at stamp time.
 * Applied only on karaoke token stamps (after `stampMediaTimeNow` / heard playhead).
 * Line-switch Marks intentionally skip this — fewer, more deliberate taps.
 */
export const TOKEN_STAMP_LOOKBACK_SECONDS = 0.12;
export const TOKEN_STAMP_MIN_GAP_SECONDS = 0.02;

export type TokenSyncStatus = "missing" | "stale" | "tokens-only" | "complete";

export type LineWindow = {
  start: number;
  end: number;
};

export function parseVariantTokenSync(raw: unknown): VariantTokenSync | null {
  const parsed = variantTokenSyncSchema.safeParse(raw);
  return parsed.success ? parsed.data : null;
}

/** Clear amber QA flags when an editor accepts auto stamps as reviewed. */
export function clearFlagsForReviewed(sync: VariantTokenSync): VariantTokenSync {
  if (!sync.flags?.length) {
    return { ...sync, source: "reviewed" };
  }
  const { flags: _flags, ...rest } = sync;
  return { ...rest, source: "reviewed" };
}

export function parsePublishedTokenSync(raw: unknown): PublishedTokenSync | null {
  const parsed = publishedTokenSyncSchema.safeParse(raw);
  return parsed.success ? parsed.data : null;
}

function textsMatch(sync: VariantTokenSync, spokenTexts: string[]): boolean {
  if (sync.lines.length !== spokenTexts.length) return false;
  return sync.lines.every(
    (line, index) => line.text.trim() === spokenTexts[index]?.trim()
  );
}

export function tokenSyncStatus(
  sync: VariantTokenSync | null,
  contentHash: string | null | undefined,
  spokenTexts: string[]
): TokenSyncStatus {
  if (!sync || sync.lines.length === 0) return "missing";
  if (!contentHash || sync.contentHash !== contentHash) return "stale";
  if (!textsMatch(sync, spokenTexts)) return "stale";
  const allStamped = sync.lines.every((line) =>
    line.tokens.every((token) => token.startSeconds != null)
  );
  return allStamped ? "complete" : "tokens-only";
}

export function tokenSyncFromSurfaces(params: {
  lines: Array<{
    text: string;
    tokens: Array<string | { text: string; reading?: string }>;
  }>;
  contentHash: string;
  lineStartSeconds?: Array<number | null | undefined> | null;
}): VariantTokenSync {
  return {
    version: TOKEN_SYNC_VERSION,
    contentHash: params.contentHash,
    lines: params.lines.map((line, lineIndex) => ({
      text: line.text,
      tokens: line.tokens.map((token, tokenIndex) => {
        const surface = typeof token === "string" ? { text: token } : token;
        return {
          text: surface.text,
          startSeconds:
            tokenIndex === 0 && params.lineStartSeconds?.[lineIndex] != null
              ? params.lineStartSeconds[lineIndex]!
              : null,
          ...(surface.reading ? { reading: surface.reading } : {}),
        };
      }),
    })),
  };
}

/** Playhead seconds for the first token of each spoken line. */
export function lineStartSecondsForTokenSync(
  windows: LineWindow[] | null,
  spokenCount: number
): Array<number | null> {
  return Array.from({ length: spokenCount }, (_, index) => {
    if (windows?.[index] != null) return windows[index].start;
    if (index === 0) return 0;
    return null;
  });
}

/** First token of each line follows the line-start mark. */
export function applyLineStartToFirstTokens(
  sync: VariantTokenSync,
  lineStartSeconds: Array<number | null | undefined>,
  options?: { overwrite?: boolean }
): VariantTokenSync {
  const overwrite = options?.overwrite === true;
  let changed = false;
  const lines = sync.lines.map((line, lineIndex) => {
    const start = lineStartSeconds[lineIndex];
    if (start == null || !Number.isFinite(start) || line.tokens.length === 0) {
      return line;
    }
    const first = line.tokens[0];
    if (!overwrite && first.startSeconds != null) return line;
    if (first.startSeconds === start) return line;
    changed = true;
    return {
      ...line,
      tokens: line.tokens.map((token, tokenIndex) =>
        tokenIndex === 0 ? { ...token, startSeconds: start } : token
      ),
    };
  });
  return changed ? { ...sync, lines } : sync;
}

/** Line windows in full-WAV seconds — same domain as the waveform playhead. */
export function spokenLineWindows(params: {
  markSamples: number[];
  spokenCount: number;
  sampleRate: number;
  totalSamples: number;
}): LineWindow[] | null {
  const { markSamples, spokenCount, sampleRate, totalSamples } = params;
  if (spokenCount <= 0 || sampleRate <= 0 || totalSamples <= 0) return null;
  const sorted = [...markSamples]
    .filter((sample) => sample > 0 && sample < totalSamples)
    .sort((a, b) => a - b);
  if (sorted.length + 1 !== spokenCount) return null;
  const starts = [0, ...sorted];
  const ends = [...sorted, totalSamples];
  return starts.map((start, index) => ({
    start: start / sampleRate,
    end: ends[index] / sampleRate,
  }));
}

export function playheadToExportSeconds(
  playheadSeconds: number,
  trimSampleLower: number | null | undefined,
  sampleRate: number
): number {
  const trimLower = trimSampleLower ?? 0;
  return playheadSeconds - trimLower / sampleRate;
}

function flattenTokens(sync: VariantTokenSync) {
  const entries: Array<{
    lineIndex: number;
    tokenIndex: number;
    startSeconds: number | null;
  }> = [];
  sync.lines.forEach((line, lineIndex) => {
    line.tokens.forEach((token, tokenIndex) => {
      entries.push({
        lineIndex,
        tokenIndex,
        startSeconds: token.startSeconds,
      });
    });
  });
  return entries;
}

function previousStamp(
  sync: VariantTokenSync,
  lineIndex: number,
  tokenIndex: number,
  window: LineWindow | null
): number {
  const entries = flattenTokens(sync);
  const index = entries.findIndex(
    (entry) => entry.lineIndex === lineIndex && entry.tokenIndex === tokenIndex
  );
  for (let i = index - 1; i >= 0; i--) {
    const value = entries[i]?.startSeconds;
    if (value != null) return value;
  }
  if (window && tokenIndex > 0) return window.start;
  return 0;
}

function proposedStampSeconds(
  clipSeconds: number,
  previous: number,
  window: LineWindow | null,
  playbackRate = 1
): number {
  const floor = Math.max(
    previous + TOKEN_STAMP_MIN_GAP_SECONDS,
    window?.start ?? 0
  );
  // Tap lag is wall-clock; scale into media time so 0.5× does not pull back
  // twice as much timeline as the user actually lagged (see wallDelayToMediaSeconds).
  // Heard playhead (latency) is already applied upstream via stampMediaTimeNow —
  // lookback here is only the human reaction offset, not a second latency pass.
  const lookback = wallDelayToMediaSeconds(
    TOKEN_STAMP_LOOKBACK_SECONDS,
    playbackRate
  );
  const pulledBack = clipSeconds - lookback;
  // Lookback models tap lag, but near a line mark it snaps every word
  // onto the same tenth. Use the live playhead in that case.
  return pulledBack > floor ? pulledBack : Math.max(clipSeconds, floor);
}

export function clampStamp(params: {
  proposed: number;
  previous: number;
  window: LineWindow | null;
}): number {
  const minNext = params.previous + TOKEN_STAMP_MIN_GAP_SECONDS;
  let next = Math.max(minNext, params.proposed);
  if (params.window) {
    const latest =
      params.window.end - TOKEN_STAMP_MIN_GAP_SECONDS > params.window.start
        ? params.window.end - TOKEN_STAMP_MIN_GAP_SECONDS
        : params.window.end;
    next = Math.min(Math.max(next, params.window.start), Math.max(latest, minNext));
    next = Math.max(next, minNext);
  }
  return Math.max(0, next);
}

function replaceToken(
  sync: VariantTokenSync,
  lineIndex: number,
  tokenIndex: number,
  startSeconds: number | null
): VariantTokenSync {
  return {
    ...sync,
    lines: sync.lines.map((line, i) =>
      i !== lineIndex
        ? line
        : {
            ...line,
            tokens: line.tokens.map((token, j) =>
              j !== tokenIndex ? token : { ...token, startSeconds }
            ),
          }
    ),
  };
}

export function stampNextToken(
  sync: VariantTokenSync,
  clipSeconds: number,
  windows: LineWindow[] | null,
  playbackRate = 1
): VariantTokenSync {
  for (let lineIndex = 0; lineIndex < sync.lines.length; lineIndex++) {
    const line = sync.lines[lineIndex];
    for (let tokenIndex = 0; tokenIndex < line.tokens.length; tokenIndex++) {
      if (line.tokens[tokenIndex].startSeconds != null) continue;
      const window = windows?.[lineIndex] ?? null;
      const previous = previousStamp(sync, lineIndex, tokenIndex, window);
      const startSeconds = clampStamp({
        proposed: proposedStampSeconds(
          clipSeconds,
          previous,
          window,
          playbackRate
        ),
        previous,
        window,
      });
      return replaceToken(sync, lineIndex, tokenIndex, startSeconds);
    }
  }
  return sync;
}

export function unstampLastToken(sync: VariantTokenSync): VariantTokenSync {
  const entries = flattenTokens(sync);
  for (let i = entries.length - 1; i >= 0; i--) {
    const entry = entries[i];
    if (entry.startSeconds == null) continue;
    return replaceToken(sync, entry.lineIndex, entry.tokenIndex, null);
  }
  return sync;
}

export function restampToken(
  sync: VariantTokenSync,
  lineIndex: number,
  tokenIndex: number,
  clipSeconds: number,
  windows: LineWindow[] | null,
  playbackRate = 1
): VariantTokenSync {
  const window = windows?.[lineIndex] ?? null;
  const previous = previousStamp(sync, lineIndex, tokenIndex, window);
  const startSeconds = clampStamp({
    proposed: proposedStampSeconds(
      clipSeconds,
      previous,
      window,
      playbackRate
    ),
    previous,
    window,
  });
  return replaceToken(sync, lineIndex, tokenIndex, startSeconds);
}

export function clearAllStamps(
  sync: VariantTokenSync,
  lineStartSeconds?: Array<number | null | undefined> | null
): VariantTokenSync {
  const next = {
    ...sync,
    lines: sync.lines.map((line, lineIndex) => ({
      ...line,
      tokens: line.tokens.map((token, tokenIndex) => ({
        ...token,
        startSeconds:
          tokenIndex === 0 && lineStartSeconds?.[lineIndex] != null
            ? lineStartSeconds[lineIndex]!
            : null,
      })),
    })),
  };
  return JSON.stringify(next) === JSON.stringify(sync) ? sync : next;
}

export function clearLineStamps(
  sync: VariantTokenSync,
  lineIndex: number,
  lineStartSeconds?: number | null
): VariantTokenSync {
  const line = sync.lines[lineIndex];
  if (!line) return sync;
  const nextTokens = line.tokens.map((token, tokenIndex) => ({
    ...token,
    startSeconds:
      tokenIndex === 0 && lineStartSeconds != null ? lineStartSeconds : null,
  }));
  if (
    line.tokens.every(
      (token, tokenIndex) => token.startSeconds === nextTokens[tokenIndex].startSeconds
    )
  ) {
    return sync;
  }
  return {
    ...sync,
    lines: sync.lines.map((row, i) =>
      i === lineIndex ? { ...row, tokens: nextTokens } : row
    ),
  };
}

/**
 * Clear stamps from `tokenIndex` onward on one line. Earlier tokens on this
 * line (and every other line) stay. If the cut includes the first word,
 * re-seed it from the line mark — same as `clearLineStamps`.
 */
export function clearStampsFrom(
  sync: VariantTokenSync,
  lineIndex: number,
  tokenIndex: number,
  lineStartSeconds?: number | null
): VariantTokenSync {
  const line = sync.lines[lineIndex];
  if (!line || tokenIndex < 0 || tokenIndex >= line.tokens.length) {
    return sync;
  }
  const nextTokens = line.tokens.map((token, index) => {
    if (index < tokenIndex) return token;
    if (index === 0 && lineStartSeconds != null) {
      return { ...token, startSeconds: lineStartSeconds };
    }
    return { ...token, startSeconds: null };
  });
  if (
    line.tokens.every(
      (token, index) => token.startSeconds === nextTokens[index].startSeconds
    )
  ) {
    return sync;
  }
  return {
    ...sync,
    lines: sync.lines.map((row, i) =>
      i === lineIndex ? { ...row, tokens: nextTokens } : row
    ),
  };
}

/**
 * Playhead for re-entering stamp rhythm after a mid-line clear: prefer the
 * token ~2 before the cut when at least two earlier stamps exist on the line,
 * otherwise the line-start window.
 */
export function seekSecondsBeforeToken(
  sync: VariantTokenSync,
  lineIndex: number,
  tokenIndex: number,
  windows: LineWindow[] | null
): number {
  const line = sync.lines[lineIndex];
  const lineStart = windows?.[lineIndex]?.start ?? (lineIndex === 0 ? 0 : null);
  if (!line || tokenIndex <= 0) {
    return lineStart ?? 0;
  }
  const earlierStamped: number[] = [];
  for (let i = 0; i < tokenIndex; i++) {
    const start = line.tokens[i]?.startSeconds;
    if (start != null) earlierStamped.push(start);
  }
  if (earlierStamped.length >= 2) {
    return earlierStamped[earlierStamped.length - 2]!;
  }
  return lineStart ?? earlierStamped[0] ?? 0;
}

export function mergeTokenWithNext(
  sync: VariantTokenSync,
  lineIndex: number,
  tokenIndex: number
): VariantTokenSync {
  const line = sync.lines[lineIndex];
  if (!line || tokenIndex < 0 || tokenIndex + 1 >= line.tokens.length) {
    return sync;
  }
  const left = line.tokens[tokenIndex];
  const right = line.tokens[tokenIndex + 1];
  const merged = {
    text: `${left.text}${right.text}`,
    startSeconds: left.startSeconds ?? right.startSeconds,
  };
  const tokens = [
    ...line.tokens.slice(0, tokenIndex),
    merged,
    ...line.tokens.slice(tokenIndex + 2),
  ];
  return {
    ...sync,
    lines: sync.lines.map((row, i) =>
      i === lineIndex ? { ...row, tokens } : row
    ),
  };
}

/**
 * Grapheme-aware end offsets into `text` (code-unit indices after each cluster).
 * Falls back to code points when `Intl.Segmenter` is unavailable.
 */
export function graphemeEndOffsets(text: string): number[] {
  if (!text) return [];
  if (typeof Intl !== "undefined" && "Segmenter" in Intl) {
    const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
    const ends: number[] = [];
    let offset = 0;
    for (const { segment } of segmenter.segment(text)) {
      offset += segment.length;
      ends.push(offset);
    }
    return ends;
  }
  const ends: number[] = [];
  let i = 0;
  while (i < text.length) {
    const codePoint = text.codePointAt(i);
    if (codePoint == null) break;
    i += String.fromCodePoint(codePoint).length;
    ends.push(i);
  }
  return ends;
}

/** Midpoint split offset in code units, or null when the surface cannot split. */
export function midpointSplitOffset(text: string): number | null {
  const ends = graphemeEndOffsets(text);
  if (ends.length < 2) return null;
  return ends[Math.floor(ends.length / 2) - 1] ?? null;
}

/**
 * Split one token into two at a code-unit offset into its surface.
 * Left keeps the original stamp; right starts untimed. By default stamps from
 * the new right token onward on that line are cleared (same spirit as
 * clear-from-here) so the user can re-stamp through the corrected chips.
 */
export function splitTokenAt(
  sync: VariantTokenSync,
  lineIndex: number,
  tokenIndex: number,
  splitOffset: number,
  options?: {
    clearFromSplit?: boolean;
    lineStartSeconds?: number | null;
  }
): VariantTokenSync {
  const line = sync.lines[lineIndex];
  if (!line || tokenIndex < 0 || tokenIndex >= line.tokens.length) {
    return sync;
  }
  const original = line.tokens[tokenIndex];
  if (
    !Number.isInteger(splitOffset) ||
    splitOffset <= 0 ||
    splitOffset >= original.text.length
  ) {
    return sync;
  }
  // Require a grapheme boundary so we never cut a surrogate pair / cluster.
  const ends = graphemeEndOffsets(original.text);
  if (!ends.includes(splitOffset)) {
    return sync;
  }

  const left = {
    text: original.text.slice(0, splitOffset),
    startSeconds: original.startSeconds,
  };
  const right = {
    text: original.text.slice(splitOffset),
    startSeconds: null as number | null,
  };
  if (!left.text || !right.text) return sync;

  let tokens = [
    ...line.tokens.slice(0, tokenIndex),
    left,
    right,
    ...line.tokens.slice(tokenIndex + 1),
  ];

  const clearFromSplit = options?.clearFromSplit !== false;
  if (clearFromSplit) {
    const rightIndex = tokenIndex + 1;
    tokens = tokens.map((token, index) => {
      if (index < rightIndex) return token;
      if (index === 0 && options?.lineStartSeconds != null) {
        return { ...token, startSeconds: options.lineStartSeconds };
      }
      return { ...token, startSeconds: null };
    });
  }

  if (!tokenRangesInLine(line.text, tokens)) {
    return sync;
  }

  return {
    ...sync,
    lines: sync.lines.map((row, i) =>
      i === lineIndex ? { ...row, tokens } : row
    ),
  };
}

export type TokenRange = {
  text: string;
  start: number;
  end: number;
  startSeconds: number | null;
  tokenIndex: number;
};

export function tokenRangesInLine(
  lineText: string,
  tokens: VariantTokenSync["lines"][number]["tokens"]
): TokenRange[] | null {
  const ranges: TokenRange[] = [];
  let searchStart = 0;
  for (let i = 0; i < tokens.length; i++) {
    const word = tokens[i].text;
    const index = lineText.indexOf(word, searchStart);
    if (index < 0) return null;
    ranges.push({
      text: word,
      start: index,
      end: index + word.length,
      startSeconds: tokens[i].startSeconds,
      tokenIndex: i,
    });
    searchStart = index + word.length;
  }
  return ranges;
}

export type LineDisplayPiece =
  | { type: "token"; range: TokenRange }
  | { type: "gap"; text: string; start: number };

export function lineDisplayPieces(
  lineText: string,
  tokens: VariantTokenSync["lines"][number]["tokens"]
): LineDisplayPiece[] | null {
  const ranges = tokenRangesInLine(lineText, tokens);
  if (!ranges) return null;
  const pieces: LineDisplayPiece[] = [];
  let cursor = 0;
  for (const range of ranges) {
    if (cursor < range.start) {
      pieces.push({
        type: "gap",
        text: lineText.slice(cursor, range.start),
        start: cursor,
      });
    }
    pieces.push({ type: "token", range });
    cursor = range.end;
  }
  if (cursor < lineText.length) {
    pieces.push({
      type: "gap",
      text: lineText.slice(cursor),
      start: cursor,
    });
  }
  return pieces;
}

export function applyTokenSelection(
  sync: VariantTokenSync,
  lineIndex: number,
  selStart: number,
  selEnd: number
): VariantTokenSync | null {
  const line = sync.lines[lineIndex];
  if (!line) return null;
  const start = Math.min(selStart, selEnd);
  const end = Math.max(selStart, selEnd);
  if (end <= start) return null;
  const trimmed = trimSelection(line.text, start, end);
  if (!trimmed) return null;
  const ranges = tokenRangesInLine(line.text, line.tokens);
  if (!ranges || ranges.length === 0) return null;

  const pieces = splitSelectionPieces(line.text, trimmed.start, trimmed.end);
  if (pieces.length === 0) return null;

  const regionStart = pieces[0].start;
  const regionEnd = pieces[pieces.length - 1].end;
  const overlapping = ranges.filter(
    (range) => range.start < regionEnd && range.end > regionStart
  );
  if (overlapping.length === 0) return null;

  const first = overlapping[0];
  const last = overlapping[overlapping.length - 1];
  const nextTokens: VariantTokenSync["lines"][number]["tokens"] = [];

  for (const range of ranges) {
    if (range.tokenIndex < first.tokenIndex) {
      nextTokens.push(line.tokens[range.tokenIndex]);
    }
  }

  if (first.start < regionStart) {
    for (const piece of splitSelectionPieces(line.text, first.start, regionStart)) {
      nextTokens.push({
        text: piece.text,
        startSeconds: piece.start === first.start ? first.startSeconds : null,
      });
    }
  }

  for (const piece of pieces) {
    nextTokens.push({
      text: piece.text,
      startSeconds: timeForSpan(ranges, piece.start, piece.end),
    });
  }

  if (last.end > regionEnd) {
    for (const piece of splitSelectionPieces(line.text, regionEnd, last.end)) {
      nextTokens.push({
        text: piece.text,
        startSeconds: null,
      });
    }
  }

  for (const range of ranges) {
    if (range.tokenIndex > last.tokenIndex) {
      nextTokens.push(line.tokens[range.tokenIndex]);
    }
  }

  const cleaned = nextTokens.filter(
    (token) => token.text.length > 0 && !isAllPunctuationOrWhitespace(token.text)
  );
  if (cleaned.length === 0) return null;
  if (!tokenRangesInLine(line.text, cleaned)) return null;
  if (tokensEqual(line.tokens, cleaned)) return null;

  return {
    ...sync,
    lines: sync.lines.map((row, i) =>
      i === lineIndex ? { ...row, tokens: cleaned } : row
    ),
  };
}

function tokensEqual(
  left: VariantTokenSync["lines"][number]["tokens"],
  right: VariantTokenSync["lines"][number]["tokens"]
): boolean {
  if (left.length !== right.length) return false;
  return left.every(
    (token, i) =>
      token.text === right[i].text && token.startSeconds === right[i].startSeconds
  );
}

function timeForSpan(
  ranges: TokenRange[],
  start: number,
  end: number
): number | null {
  const overlapping = ranges.filter(
    (range) => range.start < end && range.end > start
  );
  if (overlapping.length === 0) return null;
  const fullyCovered =
    overlapping[0].start === start &&
    overlapping[overlapping.length - 1].end === end &&
    overlapping.every((range) => range.start >= start && range.end <= end);
  return fullyCovered ? overlapping[0].startSeconds : null;
}

function trimSelection(
  text: string,
  start: number,
  end: number
): { start: number; end: number } | null {
  let s = start;
  let e = end;
  while (s < e) {
    const next = charAt(text, s);
    if (!next || !isAllPunctuationOrWhitespace(next.char)) break;
    s += next.size;
  }
  while (e > s) {
    const prev = charBefore(text, e);
    if (!prev || !isAllPunctuationOrWhitespace(prev.char)) break;
    e = prev.start;
  }
  return e > s ? { start: s, end: e } : null;
}

function splitSelectionPieces(
  text: string,
  start: number,
  end: number
): Array<{ text: string; start: number; end: number }> {
  const pieces: Array<{ text: string; start: number; end: number }> = [];
  let i = start;
  while (i < end) {
    const next = charAt(text, i);
    if (!next) break;
    if (isAllPunctuationOrWhitespace(next.char)) {
      i += next.size;
      continue;
    }
    let j = i + next.size;
    while (j < end) {
      const following = charAt(text, j);
      if (!following || isAllPunctuationOrWhitespace(following.char)) break;
      j += following.size;
    }
    pieces.push({ text: text.slice(i, j), start: i, end: j });
    i = j;
  }
  return pieces;
}

function charAt(
  text: string,
  index: number
): { char: string; size: number } | null {
  if (index < 0 || index >= text.length) return null;
  const codePoint = text.codePointAt(index);
  if (codePoint == null) return null;
  const char = String.fromCodePoint(codePoint);
  return { char, size: char.length };
}

function charBefore(
  text: string,
  end: number
): { char: string; start: number } | null {
  if (end <= 0 || end > text.length) return null;
  if (
    end >= 2 &&
    text.charCodeAt(end - 1) >= 0xdc00 &&
    text.charCodeAt(end - 1) <= 0xdfff &&
    text.charCodeAt(end - 2) >= 0xd800 &&
    text.charCodeAt(end - 2) <= 0xdbff
  ) {
    return { char: text.slice(end - 2, end), start: end - 2 };
  }
  return { char: text[end - 1], start: end - 1 };
}

export function shiftTokenSyncSeconds(
  sync: VariantTokenSync,
  shift: (seconds: number) => number | null
): VariantTokenSync {
  return {
    ...sync,
    lines: sync.lines.map((line) => ({
      ...line,
      tokens: line.tokens.map((token) => {
        if (token.startSeconds == null) return token;
        const next = shift(token.startSeconds);
        return { ...token, startSeconds: next };
      }),
    })),
  };
}

export function activeTokenIndexForTime(
  sync: VariantTokenSync | PublishedTokenSync,
  lineIndex: number,
  timeSeconds: number
): number | null {
  const line = sync.lines[lineIndex];
  if (!line) return null;
  let active: number | null = null;
  for (let i = 0; i < line.tokens.length; i++) {
    const start = line.tokens[i].startSeconds;
    if (start == null) break;
    if (timeSeconds >= start) active = i;
    else break;
  }
  return active;
}

/**
 * Latest stamped token whose start is at or before `timeSeconds`, across all
 * lines. Used for review-queue / full-take karaoke follow.
 */
export function activeTokenAtTime(
  lines: Array<{ tokens: Array<{ startSeconds?: number | null }> }>,
  timeSeconds: number
): { lineIndex: number; tokenIndex: number } | null {
  let best: { lineIndex: number; tokenIndex: number; start: number } | null =
    null;
  for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    const tokens = lines[lineIndex]?.tokens ?? [];
    for (let tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
      const start = tokens[tokenIndex]?.startSeconds;
      if (start == null) continue;
      if (timeSeconds >= start && (!best || start >= best.start)) {
        best = { lineIndex, tokenIndex, start };
      }
    }
  }
  return best
    ? { lineIndex: best.lineIndex, tokenIndex: best.tokenIndex }
    : null;
}

export function exportLineWindows(params: {
  lineSwitchSeconds: number[];
  spokenCount: number;
  durationSeconds: number;
}): LineWindow[] | null {
  if (params.spokenCount <= 0 || params.durationSeconds <= 0) return null;
  if (params.lineSwitchSeconds.length + 1 !== params.spokenCount) return null;
  const starts = [0, ...params.lineSwitchSeconds];
  const ends = [...params.lineSwitchSeconds, params.durationSeconds];
  return starts.map((start, index) => ({
    start,
    end: ends[index],
  }));
}

export function estimatedWavDurationSeconds(params: {
  audioByteCount: number;
  sampleRate: number;
  trimSampleLower?: number | null;
  trimSampleUpper?: number | null;
}): number {
  const totalSamples = Math.max(
    0,
    Math.floor((params.audioByteCount - 44) / 2)
  );
  const lo = params.trimSampleLower ?? 0;
  const hi = params.trimSampleUpper ?? totalSamples;
  if (params.sampleRate <= 0) return 0;
  return Math.max(0, (hi - lo) / params.sampleRate);
}

export function shiftTokenSyncBySamples(
  raw: unknown,
  sampleRate: number,
  mapSample: (sample: number) => number | null
): VariantTokenSync | null {
  const sync = parseVariantTokenSync(raw);
  if (!sync || sampleRate <= 0) return null;
  return shiftTokenSyncSeconds(sync, (seconds) => {
    const sample = Math.round(seconds * sampleRate);
    const next = mapSample(sample);
    if (next == null) return null;
    return next / sampleRate;
  });
}

export function publishedTokenSyncFromWorking(params: {
  sync: VariantTokenSync;
  variantId: string;
  contentHash: string;
  spokenTexts: string[];
  windows: LineWindow[] | null;
  trimSampleLower?: number | null;
  sampleRate: number;
}): PublishedTokenSync | null {
  const { sync, variantId, contentHash, spokenTexts, windows, sampleRate } =
    params;
  if (sync.version !== TOKEN_SYNC_VERSION) return null;
  if (sync.contentHash !== contentHash) return null;
  if (!textsMatch(sync, spokenTexts)) return null;

  const lines: PublishedTokenSync["lines"] = [];
  let previous = -TOKEN_STAMP_MIN_GAP_SECONDS;
  for (let lineIndex = 0; lineIndex < sync.lines.length; lineIndex++) {
    const line = sync.lines[lineIndex];
    const window =
      windows && windows.length === sync.lines.length
        ? windows[lineIndex]
        : null;
    const tokens: PublishedTokenSync["lines"][number]["tokens"] = [];
    for (const token of line.tokens) {
      if (token.startSeconds == null || !Number.isFinite(token.startSeconds)) {
        return null;
      }
      let exportSeconds = Math.max(
        0,
        playheadToExportSeconds(
          token.startSeconds,
          params.trimSampleLower,
          sampleRate
        )
      );
      if (window) {
        const latest =
          window.end - TOKEN_STAMP_MIN_GAP_SECONDS > window.start
            ? window.end - TOKEN_STAMP_MIN_GAP_SECONDS
            : Math.max(window.start, window.end - 0.001);
        exportSeconds = Math.min(
          Math.max(exportSeconds, window.start),
          latest
        );
      }
      exportSeconds = Math.max(
        exportSeconds,
        previous + TOKEN_STAMP_MIN_GAP_SECONDS
      );
      let rounded = roundSeconds(exportSeconds);
      if (rounded <= previous) {
        rounded = roundSeconds(previous + TOKEN_STAMP_MIN_GAP_SECONDS);
      }
      previous = rounded;
      tokens.push({
        text: token.text,
        startSeconds: rounded,
      });
    }
    if (tokens.length === 0) return null;
    lines.push({ text: line.text, tokens });
  }

  const published = publishedTokenSyncSchema.safeParse({
    version: TOKEN_SYNC_VERSION,
    variantId,
    contentHash,
    lines,
    ...(sync.source ? { source: sync.source } : {}),
  });
  return published.success ? published.data : null;
}

export function completeTokenSyncForVariant(params: {
  tokenSync: unknown;
  variantId: string;
  contentHash: string | null | undefined;
  spokenTexts: string[];
  lineSwitchSeconds: number[];
  durationSeconds: number;
  trimSampleLower?: number | null;
  sampleRate: number;
}): PublishedTokenSync | null {
  if (!params.contentHash) return null;
  const working = parseVariantTokenSync(params.tokenSync);
  if (!working) return null;
  const windows = exportLineWindows({
    lineSwitchSeconds: params.lineSwitchSeconds,
    spokenCount: params.spokenTexts.length,
    durationSeconds: params.durationSeconds,
  });
  return publishedTokenSyncFromWorking({
    sync: working,
    variantId: params.variantId,
    contentHash: params.contentHash,
    spokenTexts: params.spokenTexts,
    windows,
    trimSampleLower: params.trimSampleLower,
    sampleRate: params.sampleRate,
  });
}

function roundSeconds(value: number): number {
  return Math.round(value * 1000) / 1000;
}
