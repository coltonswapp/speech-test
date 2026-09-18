/**
 * Auto-stamp post-process: turns raw forced-aligner token starts into a
 * Studio-shaped working tokenSync plus derived line-switch marks.
 *
 * Port of docs/karaoke-autotiming/postprocess.py, with the constant shift
 * re-fitted against RMS speech onsets instead of one editor's taps (KA-3).
 * Pure: no I/O, so it is testable with synthetic RMS tracks and runnable
 * offline by the eval script.
 */
import { clampStamp, TOKEN_SYNC_VERSION, TOKEN_STAMP_MIN_GAP_SECONDS, type LineWindow } from "@/lib/dialogue/token-sync";
import type { TokenSyncFlag, VariantTokenSync } from "@/lib/dialogue/types";
import { quietThresholdFromRms, rmsTrack } from "@/lib/tts/alignment";

/**
 * Subtracted from every non-first raw CTC start. Raw MMS_FA starts sit a
 * median 26 ms *after* the RMS onset on 689 clean post-pause tokens across
 * the 38 gold scenes (per-scene sd 19 ms); 65 ms lands stamps ~40 ms before
 * onset. Decided 2026-09-18: anchor to onsets, not to the human gold (editors
 * tap ~95 ms before onset, so this scores worse against them by design) and
 * not to the published catalog. The eval (KA-6) measures against onsets.
 * Retune here, and only here, if auto stamps feel late after real review.
 */
export const AUTO_STAMP_SHIFT_SECONDS = 0.065;
/** Onset search: walk back through continuous speech at most this far. */
export const AUTO_STAMP_MAX_SNAP_BACK_SECONDS = 0.35;
/** Onset search: when the raw start sits in silence, look ahead at most this far. */
export const AUTO_STAMP_MAX_SNAP_FORWARD_SECONDS = 0.25;
/** Derived line mark sits in the gap, this far before the next speaker's onset. */
export const MARK_LEAD_MIN_SECONDS = 0.08;
export const MARK_LEAD_MAX_SECONDS = 0.25;
/** A gap shorter than this cannot hold a mark without clipping speech. */
export const NO_GAP_MIN_SECONDS = 0.06;
/** A token is "post-pause" when at least this much silence precedes its onset. */
export const POST_PAUSE_MIN_QUIET_SECONDS = 0.15;
/** stamp-in-silence: stamp is in a quiet frame and no speech starts within this window. */
export const STAMP_IN_SILENCE_LOOKAHEAD_SECONDS = 0.06;
/** script-mismatch: line mean CTC score below this fraction of the scene median. Gold lines never drop below 0.36. */
export const SCRIPT_MISMATCH_RATIO = 0.35;
const RMS_WINDOW_SECONDS = 0.01;
const MAX_GAP_SCAN_SECONDS = 1.5;

export type AlignedToken = {
  startSeconds: number;
  endSeconds: number;
  score: number;
  readingFallback: boolean;
};
export type AlignedLine = { tokens: AlignedToken[]; score: number };

export type AutoStampInput = {
  alignerVersion: string;
  aligned: AlignedLine[];
  lines: Array<{ text: string; tokens: Array<{ text: string; reading?: string }> }>;
  samples: Float32Array;
  sampleRate: number;
  contentHash: string;
  /** Existing marks (full-WAV samples). Used as-is when there is one per line boundary. */
  existingMarkSamples?: number[] | null;
  options?: { shiftSeconds?: number };
};

export type AutoStampResult = {
  tokenSync: VariantTokenSync;
  /** Full-WAV sample marks, one per line boundary. */
  markSamples: number[];
  /** True when marks were derived here rather than taken from the variant. */
  marksDerived: boolean;
  flags: TokenSyncFlag[];
};

type Track = {
  rms: number[];
  threshold: number;
  windowSeconds: number;
};

function buildTrack(samples: Float32Array, sampleRate: number): Track {
  const windowSamples = Math.max(1, Math.round(sampleRate * RMS_WINDOW_SECONDS));
  const rms = rmsTrack(samples, windowSamples);
  return {
    rms,
    threshold: quietThresholdFromRms(rms),
    windowSeconds: windowSamples / sampleRate,
  };
}

function frameOf(track: Track, seconds: number): number {
  const k = Math.floor(seconds / track.windowSeconds);
  return Math.min(Math.max(k, 0), track.rms.length - 1);
}

function isLoud(track: Track, frame: number): boolean {
  return track.rms[frame] >= track.threshold;
}

/**
 * Acoustic onset of the speech run around `seconds`: walk back while frames
 * are loud (bounded), or forward to the next loud frame when the start sits
 * in silence. Returns `seconds` unchanged for long continuous speech.
 */
export function speechOnsetNear(
  track: Track,
  seconds: number,
  maxBackSeconds = AUTO_STAMP_MAX_SNAP_BACK_SECONDS
): number {
  const n = track.rms.length;
  if (n === 0) return seconds;
  const k = frameOf(track, seconds);
  if (!isLoud(track, k)) {
    const limit = Math.round(AUTO_STAMP_MAX_SNAP_FORWARD_SECONDS / track.windowSeconds);
    let j = k;
    while (j < n - 1 && !isLoud(track, j) && j - k < limit) j++;
    return j * track.windowSeconds;
  }
  const limit = Math.round(maxBackSeconds / track.windowSeconds);
  let j = k;
  while (j > 0 && isLoud(track, j - 1) && k - j < limit) j--;
  if (k - j >= limit) return seconds;
  return j * track.windowSeconds;
}

/** Seconds of silence immediately before `onsetSeconds` (bounded scan). */
function quietBefore(track: Track, onsetSeconds: number): number {
  const k = frameOf(track, onsetSeconds);
  const limit = Math.round(MAX_GAP_SCAN_SECONDS / track.windowSeconds);
  let j = k;
  while (j > 0 && !isLoud(track, j - 1) && k - j < limit) j--;
  return (k - j) * track.windowSeconds;
}

function speechWithin(track: Track, fromSeconds: number, spanSeconds: number): boolean {
  const from = frameOf(track, fromSeconds);
  const to = frameOf(track, fromSeconds + spanSeconds);
  for (let f = from; f <= to; f++) if (isLoud(track, f)) return true;
  return false;
}

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/**
 * Line-switch marks from each later line's first-token onset: gap midpoint,
 * clamped to 80–250 ms before the onset, never earlier than the previous
 * speaker's last sound. Returns seconds plus `no-gap` flags.
 */
export function deriveLineMarks(
  track: Track,
  aligned: AlignedLine[],
  durationSeconds: number
): { markSeconds: number[]; flags: TokenSyncFlag[] } {
  const markSeconds: number[] = [];
  const flags: TokenSyncFlag[] = [];
  for (let li = 1; li < aligned.length; li++) {
    const first = aligned[li].tokens[0];
    const rawStart = first?.startSeconds ?? 0;
    const onset = speechOnsetNear(track, rawStart);
    const gap = quietBefore(track, onset);
    let lead = Math.min(Math.max(gap / 2, MARK_LEAD_MIN_SECONDS), MARK_LEAD_MAX_SECONDS);
    if (gap < NO_GAP_MIN_SECONDS) {
      flags.push({
        code: "no-gap",
        lineIndex: li,
        detail: `${Math.round(gap * 1000)} ms of silence before line onset`,
      });
      lead = Math.max(gap / 2, TOKEN_STAMP_MIN_GAP_SECONDS);
    } else if (gap < 2 * MARK_LEAD_MIN_SECONDS) {
      lead = gap / 2;
    }
    let mark = onset - lead;
    const previous = markSeconds[markSeconds.length - 1] ?? 0;
    mark = Math.max(mark, previous + TOKEN_STAMP_MIN_GAP_SECONDS);
    mark = Math.min(mark, Math.max(previous + TOKEN_STAMP_MIN_GAP_SECONDS, durationSeconds - TOKEN_STAMP_MIN_GAP_SECONDS));
    markSeconds.push(mark);
  }
  return { markSeconds, flags };
}

function windowsFromMarks(markSeconds: number[], durationSeconds: number): LineWindow[] {
  const starts = [0, ...markSeconds];
  const ends = [...markSeconds, durationSeconds];
  return starts.map((start, i) => ({ start, end: ends[i] }));
}

export function autoStampTokenSync(input: AutoStampInput): AutoStampResult {
  const { aligned, lines, samples, sampleRate } = input;
  if (aligned.length !== lines.length) {
    throw new Error(`aligner returned ${aligned.length} lines for ${lines.length}`);
  }
  const shift = input.options?.shiftSeconds ?? AUTO_STAMP_SHIFT_SECONDS;
  const durationSeconds = samples.length / sampleRate;
  const track = buildTrack(samples, sampleRate);
  const flags: TokenSyncFlag[] = [];

  // Marks: keep the editor's when complete, otherwise derive.
  const existing = input.existingMarkSamples ?? [];
  let markSeconds: number[];
  let marksDerived: boolean;
  if (lines.length >= 1 && existing.length === lines.length - 1) {
    markSeconds = existing.map((s) => s / sampleRate);
    marksDerived = false;
  } else {
    const derived = deriveLineMarks(track, aligned, durationSeconds);
    markSeconds = derived.markSeconds;
    flags.push(...derived.flags);
    marksDerived = true;
  }
  const windows = windowsFromMarks(markSeconds, durationSeconds);

  // script-mismatch: a line whose CTC confidence collapses relative to the take.
  const sceneMedian = median(aligned.map((line) => line.score));
  const mismatched = new Set<number>();
  aligned.forEach((line, li) => {
    if (sceneMedian > 0 && line.score < SCRIPT_MISMATCH_RATIO * sceneMedian) {
      mismatched.add(li);
      flags.push({
        code: "script-mismatch",
        lineIndex: li,
        detail: `line score ${line.score.toFixed(2)} vs take median ${sceneMedian.toFixed(2)}`,
      });
    }
  });

  let previous = -TOKEN_STAMP_MIN_GAP_SECONDS;
  const outLines: VariantTokenSync["lines"] = lines.map((line, li) => {
    const window = windows[li];
    const tokens = line.tokens.map((token, ti) => {
      const raw = aligned[li].tokens[ti];
      if (token.reading && raw.readingFallback) {
        flags.push({ code: "reading-fallback", lineIndex: li, tokenIndex: ti });
      }
      let startSeconds: number | null;
      if (ti === 0) {
        // Studio convention: the first token follows the line mark.
        startSeconds = window.start;
      } else if (mismatched.has(li)) {
        startSeconds = null;
      } else {
        startSeconds = clampStamp({
          proposed: raw.startSeconds - shift,
          previous,
          window,
        });
        // stamp-in-silence, post-pause tokens only (where an onset is expected).
        const onset = speechOnsetNear(track, raw.startSeconds);
        const postPause = quietBefore(track, onset) >= POST_PAUSE_MIN_QUIET_SECONDS;
        if (
          postPause &&
          !isLoud(track, frameOf(track, startSeconds)) &&
          !speechWithin(track, startSeconds, STAMP_IN_SILENCE_LOOKAHEAD_SECONDS)
        ) {
          flags.push({ code: "stamp-in-silence", lineIndex: li, tokenIndex: ti });
        }
      }
      if (startSeconds != null) {
        startSeconds = Math.round(startSeconds * 1000) / 1000;
        previous = startSeconds;
      }
      return {
        text: token.text,
        startSeconds,
        ...(token.reading ? { reading: token.reading } : {}),
      };
    });
    return { text: line.text, tokens };
  });

  flags.sort((a, b) => a.lineIndex - b.lineIndex || (a.tokenIndex ?? -1) - (b.tokenIndex ?? -1));

  return {
    tokenSync: {
      version: TOKEN_SYNC_VERSION,
      contentHash: input.contentHash,
      lines: outLines,
      source: "auto",
      alignerVersion: input.alignerVersion,
      ...(flags.length ? { flags } : {}),
    },
    markSamples: markSeconds.map((s) => Math.round(s * sampleRate)),
    marksDerived,
    flags,
  };
}
