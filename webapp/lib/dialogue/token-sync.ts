import { isAllPunctuationOrWhitespace } from "@/lib/dialogue/japanese-segmentation";
import {
  publishedTokenSyncSchema,
  variantTokenSyncSchema,
  type PublishedTokenSync,
  type VariantTokenSync,
} from "@/lib/dialogue/types";

export const TOKEN_SYNC_VERSION = 1 as const;
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
  lines: Array<{ text: string; tokens: string[] }>;
  contentHash: string;
  lineStartSeconds?: number[] | null;
}): VariantTokenSync {
  return {
    version: TOKEN_SYNC_VERSION,
    contentHash: params.contentHash,
    lines: params.lines.map((line, lineIndex) => ({
      text: line.text,
      tokens: line.tokens.map((text, tokenIndex) => ({
        text,
        startSeconds:
          tokenIndex === 0 && params.lineStartSeconds?.[lineIndex] != null
            ? params.lineStartSeconds[lineIndex]
            : null,
      })),
    })),
  };
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
  tokenIndex: number
): number {
  const entries = flattenTokens(sync);
  const index = entries.findIndex(
    (entry) => entry.lineIndex === lineIndex && entry.tokenIndex === tokenIndex
  );
  for (let i = index - 1; i >= 0; i--) {
    const value = entries[i]?.startSeconds;
    if (value != null) return value;
  }
  return 0;
}

function clampStamp(params: {
  proposed: number;
  previous: number;
  window: LineWindow | null;
}): number {
  let next = Math.max(
    params.previous + TOKEN_STAMP_MIN_GAP_SECONDS,
    params.proposed
  );
  if (params.window) {
    const latest =
      params.window.end - TOKEN_STAMP_MIN_GAP_SECONDS > params.window.start
        ? params.window.end - TOKEN_STAMP_MIN_GAP_SECONDS
        : params.window.end;
    next = Math.min(Math.max(next, params.window.start), latest);
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
  windows: LineWindow[] | null
): VariantTokenSync {
  for (let lineIndex = 0; lineIndex < sync.lines.length; lineIndex++) {
    const line = sync.lines[lineIndex];
    for (let tokenIndex = 0; tokenIndex < line.tokens.length; tokenIndex++) {
      if (line.tokens[tokenIndex].startSeconds != null) continue;
      const previous = previousStamp(sync, lineIndex, tokenIndex);
      const proposed = clipSeconds - TOKEN_STAMP_LOOKBACK_SECONDS;
      const startSeconds = clampStamp({
        proposed,
        previous,
        window: windows?.[lineIndex] ?? null,
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
  windows: LineWindow[] | null
): VariantTokenSync {
  const previous = previousStamp(sync, lineIndex, tokenIndex);
  const proposed = clipSeconds - TOKEN_STAMP_LOOKBACK_SECONDS;
  const startSeconds = clampStamp({
    proposed,
    previous,
    window: windows?.[lineIndex] ?? null,
  });
  return replaceToken(sync, lineIndex, tokenIndex, startSeconds);
}

export function clearLineStamps(
  sync: VariantTokenSync,
  lineIndex: number
): VariantTokenSync {
  const line = sync.lines[lineIndex];
  if (!line) return sync;
  if (line.tokens.every((token) => token.startSeconds == null)) return sync;
  return {
    ...sync,
    lines: sync.lines.map((row, i) =>
      i === lineIndex
        ? {
            ...row,
            tokens: row.tokens.map((token) => ({ ...token, startSeconds: null })),
          }
        : row
    ),
  };
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
      nextTokens.push({
        text: range.text,
        startSeconds: range.startSeconds,
      });
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
      nextTokens.push({
        text: range.text,
        startSeconds: range.startSeconds,
      });
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
  if (!windows || windows.length !== sync.lines.length) return null;

  const lines: PublishedTokenSync["lines"] = [];
  let previous = -TOKEN_STAMP_MIN_GAP_SECONDS;
  for (let lineIndex = 0; lineIndex < sync.lines.length; lineIndex++) {
    const line = sync.lines[lineIndex];
    const window = windows[lineIndex];
    const tokens: PublishedTokenSync["lines"][number]["tokens"] = [];
    for (const token of line.tokens) {
      if (token.startSeconds == null || !Number.isFinite(token.startSeconds)) {
        return null;
      }
      const exportSeconds = Math.max(
        0,
        playheadToExportSeconds(
          token.startSeconds,
          params.trimSampleLower,
          sampleRate
        )
      );
      if (exportSeconds <= previous) return null;
      if (exportSeconds < window.start) return null;
      if (exportSeconds >= window.end) return null;
      previous = exportSeconds;
      tokens.push({
        text: token.text,
        startSeconds: roundSeconds(exportSeconds),
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
