// Port of TTSCore/Sources/TTSCore/TTSAudioAlignment.swift — VAD-based sentence
// alignment for a single assembled utterance buffer. Only the paths needed for
// server-side, non-incremental alignment (Phase 2 v1) are ported: RMS-based VAD
// region detection, proportional boundary fallback, and DP-based boundary
// matching against silence candidates. Marker-silence and dialogue line-switch
// paths are not yet ported (not needed until conversation-mode / manual line
// marking lands).

export type AlignedAudioLine = {
  text: string;
  sampleRange: [number, number]; // half-open [lower, upper)
};

function rmsOfSlice(samples: Float32Array, lo: number, hi: number): number {
  if (hi <= lo) return 0;
  let sum = 0;
  for (let i = lo; i < hi; i++) {
    const s = samples[i];
    sum += s * s;
  }
  return Math.sqrt(sum / (hi - lo));
}

export function vadSpeechRegions(
  samples: Float32Array,
  sampleRate: number,
  minSilenceSeconds = 0.18,
  minSpeechSeconds = 0.06
): Array<[number, number]> {
  if (samples.length === 0) return [];
  const windowSamples = Math.max(1, Math.round(sampleRate * 0.02));
  const minSilenceSamples = Math.max(1, Math.round(sampleRate * minSilenceSeconds));
  const minSpeechSamples = Math.max(1, Math.round(sampleRate * minSpeechSeconds));

  const rms: number[] = [];
  for (let i = 0; i < samples.length; i += windowSamples) {
    const end = Math.min(i + windowSamples, samples.length);
    rms.push(rmsOfSlice(samples, i, end));
  }
  if (rms.length === 0) return [];

  const sorted = [...rms].sort((a, b) => a - b);
  const floorIdx = Math.max(0, Math.min(sorted.length - 1, Math.floor(sorted.length * 0.1)));
  const maxRms = sorted[sorted.length - 1] ?? 0;
  const floor = sorted[floorIdx];
  const enterThreshold = Math.max(floor * 2.5, floor + (maxRms - floor) * 0.08, 0.005);
  const exitThreshold = Math.max(floor * 1.6, floor + (maxRms - floor) * 0.04, 0.003);

  const regions: Array<[number, number]> = [];
  let inSpeech = false;
  let regionStart = 0;
  let silenceRun = 0;

  for (let k = 0; k < rms.length; k++) {
    const r = rms[k];
    const sampleStart = k * windowSamples;
    const sampleEnd = Math.min(samples.length, sampleStart + windowSamples);

    if (inSpeech) {
      if (r < exitThreshold) {
        silenceRun += sampleEnd - sampleStart;
        if (silenceRun >= minSilenceSamples) {
          const regionEnd = sampleStart - (silenceRun - (sampleEnd - sampleStart));
          const adjustedEnd = Math.max(regionStart + 1, regionEnd);
          regions.push([regionStart, adjustedEnd]);
          inSpeech = false;
          silenceRun = 0;
        }
      } else {
        silenceRun = 0;
      }
    } else if (r >= enterThreshold) {
      regionStart = sampleStart;
      inSpeech = true;
      silenceRun = 0;
    }
  }
  if (inSpeech) {
    regions.push([regionStart, samples.length]);
  }

  return regions.filter(([lo, hi]) => hi - lo >= minSpeechSamples);
}

function proportionalBoundaries(weights: number[], total: number): number[] {
  const n = weights.length;
  if (n < 2 || total <= 0) return [];
  const totalW = weights.reduce((a, b) => a + b, 0);
  if (totalW <= 0) return [];
  const cuts: number[] = [];
  let cum = 0;
  for (let i = 0; i < n - 1; i++) {
    cum += weights[i];
    const r = cum / totalW;
    const c = Math.round(total * r);
    cuts.push(Math.min(Math.max(0, c), total - 1));
  }
  for (let i = 1; i < cuts.length; i++) {
    if (cuts[i] <= cuts[i - 1]) {
      cuts[i] = Math.min(total - 1, cuts[i - 1] + 1);
    }
  }
  return cuts;
}

function boundariesMatchingProportional(
  proportional: number[],
  silenceCandidates: number[]
): number[] {
  const k = proportional.length;
  if (k === 0) return [];
  const mids = [...new Set(silenceCandidates)].sort((a, b) => a - b);
  const m = mids.length;
  if (m < k) return proportional;

  const inf = Number.MAX_SAFE_INTEGER / 8;
  const dp: number[][] = Array.from({ length: k }, () => new Array(m).fill(inf));
  const trace: number[][] = Array.from({ length: k }, () => new Array(m).fill(-1));

  for (let j = 0; j < m; j++) {
    dp[0][j] = Math.abs(mids[j] - proportional[0]);
  }
  for (let i = 1; i < k; i++) {
    for (let j = i; j < m; j++) {
      let best = inf;
      let bestPrev = -1;
      for (let p = i - 1; p < j; p++) {
        const v = dp[i - 1][p] + Math.abs(mids[j] - proportional[i]);
        if (v < best) {
          best = v;
          bestPrev = p;
        }
      }
      dp[i][j] = best;
      trace[i][j] = bestPrev;
    }
  }

  let endIdx = k - 1;
  let bestTotal = inf;
  for (let j = k - 1; j < m; j++) {
    if (dp[k - 1][j] < bestTotal) {
      bestTotal = dp[k - 1][j];
      endIdx = j;
    }
  }

  const path: number[] = [];
  let j = endIdx;
  for (let i = k - 1; i >= 0; i--) {
    path.push(mids[j]);
    if (i > 0) j = trace[i][j];
  }
  path.reverse();
  return path;
}

function speechOnsetCandidates(
  vad: Array<[number, number]>,
  samples: Float32Array,
  sampleRate: number
): number[] {
  if (vad.length === 0) return [];
  const candidates = new Set<number>();

  for (let index = 1; index < vad.length; index++) {
    candidates.add(vad[index][0]);
  }

  for (let i = 1; i < vad.length; i++) {
    const [lo, hi] = vad[i];
    const slice = samples.subarray(lo, hi);
    if (slice.length === 0) continue;
    const subsegments = vadSpeechRegions(slice, sampleRate, 0.08, 0.04);
    for (const [subLo] of subsegments) {
      candidates.add(lo + subLo);
    }
  }

  return [...candidates].sort((a, b) => a - b);
}

function argminAverageAbs(
  samples: Float32Array,
  lo: number,
  hi: number,
  window: number
): number {
  if (lo > hi || lo < 0 || hi >= samples.length) {
    return Math.min(Math.max(0, lo), Math.max(0, samples.length - 1));
  }
  let bestIdx = Math.floor((lo + hi) / 2);
  let bestE = Number.POSITIVE_INFINITY;
  const step = Math.max(1, Math.floor(window / 3));
  for (let i = lo; i <= hi; i += step) {
    const a = Math.max(lo, i - Math.floor(window / 2));
    const b = Math.min(samples.length - 1, i + Math.floor(window / 2));
    let sum = 0;
    let cnt = 0;
    for (let k = a; k <= b; k++) {
      sum += Math.abs(samples[k]);
      cnt++;
    }
    const e = cnt > 0 ? sum / cnt : Number.POSITIVE_INFINITY;
    if (e < bestE) {
      bestE = e;
      bestIdx = i;
    }
  }
  return bestIdx;
}

function snapProportionalToQuietSamples(
  proportional: number[],
  samples: Float32Array,
  sampleRate: number,
  total: number
): number[] {
  if (proportional.length === 0 || samples.length === 0) return proportional;
  const searchHalf = Math.max(1, Math.round(sampleRate * 0.48));
  const win = Math.max(1, Math.round(sampleRate * 0.022));
  const minSep = Math.max(320, Math.round(sampleRate * 0.045));
  const out: number[] = [];
  let lastCut = 0;
  proportional.forEach((p, idx) => {
    const tailSlots = proportional.length - idx;
    const lo = Math.max(lastCut + minSep, p - searchHalf);
    const hi = Math.min(total - tailSlots * minSep, p + searchHalf);
    let chosen: number;
    if (lo < hi) {
      chosen = argminAverageAbs(samples, lo, hi - 1, win);
    } else {
      chosen = Math.min(Math.max(lastCut + minSep, p), total - 1);
    }
    out.push(chosen);
    lastCut = chosen;
  });
  return out;
}

function contiguousRanges(
  boundaries: number[],
  total: number,
  count: number
): Array<[number, number]> {
  const starts = [0, ...boundaries];
  const ends = [...boundaries, total];
  for (let i = 0; i < starts.length; i++) {
    if (i > 0 && starts[i] <= ends[i - 1]) starts[i] = ends[i - 1];
    if (ends[i] <= starts[i]) ends[i] = Math.min(total, starts[i] + 1);
    if (starts[i] >= total) starts[i] = Math.max(0, total - 1);
    if (ends[i] > total) ends[i] = total;
  }
  const ranges: Array<[number, number]> = [];
  for (let i = 0; i < count; i++) {
    const lo = Math.max(0, Math.min(total, starts[i]));
    const hi = Math.max(lo, Math.min(total, ends[i]));
    ranges.push([lo, hi]);
  }
  return ranges;
}

/** Studio break-suggestion lead-in: how far a suggested line-switch mark is backed off from the next speaker's detected onset. */
export const SUGGESTED_BREAK_LEAD_IN_SECONDS = 0.08;

function quietRMSThreshold(samples: Float32Array, windowSamples: number): number {
  const rms: number[] = [];
  for (let i = 0; i < samples.length; i += windowSamples) {
    const end = Math.min(i + windowSamples, samples.length);
    rms.push(rmsOfSlice(samples, i, end));
  }
  const sorted = [...rms].sort((a, b) => a - b);
  const maxRms = sorted[sorted.length - 1];
  if (maxRms === undefined) return 0.003;
  const floorIdx = Math.max(0, Math.min(sorted.length - 1, Math.floor(sorted.length * 0.1)));
  const floor = sorted[floorIdx];
  return Math.max(floor * 1.6, floor + (maxRms - floor) * 0.04, 0.003);
}

/**
 * Shifts each boundary (defined as the next line's onset) earlier by up to `leadInSeconds`,
 * but never past the start of the quiet gap in front of it — so a mark backs into silence,
 * never into the previous speaker's audio, even when the gap is shorter than the lead-in.
 */
export function leadInAdjustedBoundaries(
  boundaries: number[],
  samples: Float32Array,
  sampleRate: number,
  leadInSeconds = SUGGESTED_BREAK_LEAD_IN_SECONDS
): number[] {
  if (boundaries.length === 0 || samples.length <= 1 || sampleRate <= 0) return boundaries;

  const leadInSamples = Math.max(0, Math.round(leadInSeconds * sampleRate));
  const maxScanSamples = Math.round(sampleRate * 0.5);
  const windowSamples = Math.max(1, Math.round(sampleRate * 0.01));
  const quietThreshold = quietRMSThreshold(samples, windowSamples);

  const out: number[] = [];
  for (const boundary of boundaries) {
    const onset = Math.min(Math.max(boundary, 1), samples.length - 1);
    let quietRunStart = onset;
    while (quietRunStart > 0 && onset - quietRunStart < maxScanSamples) {
      const lo = Math.max(0, quietRunStart - windowSamples);
      if (rmsOfSlice(samples, lo, quietRunStart) >= quietThreshold) break;
      quietRunStart = lo;
    }
    let adjusted = Math.max(onset - leadInSamples, quietRunStart, 1);
    const previous = out[out.length - 1];
    if (previous !== undefined) adjusted = Math.max(adjusted, previous + 1);
    out.push(Math.min(adjusted, samples.length - 1));
  }
  return out;
}

/** Assigns contiguous sample ranges to `lines` inside one assembled utterance buffer. */
export function align(
  lines: string[],
  samples: Float32Array,
  sampleRate: number
): AlignedAudioLine[] {
  const trimmed = lines.map((l) => l.trim()).filter((l) => l.length > 0);
  const total = samples.length;
  if (trimmed.length === 0 || total === 0) return [];

  if (trimmed.length === 1) {
    return [{ text: trimmed[0], sampleRange: [0, total] }];
  }

  const weights = trimmed.map((t) => Math.max(1, t.length));
  const proportional = proportionalBoundaries(weights, total);
  const vad = vadSpeechRegions(samples, sampleRate);

  let boundaries: number[];
  if (vad.length === trimmed.length) {
    boundaries = vad.slice(1).map(([lo]) => lo);
  } else {
    const onsetCandidates = speechOnsetCandidates(vad, samples, sampleRate);
    if (onsetCandidates.length >= trimmed.length - 1) {
      boundaries = boundariesMatchingProportional(proportional, onsetCandidates);
    } else {
      boundaries = snapProportionalToQuietSamples(proportional, samples, sampleRate, total);
    }
  }

  const ranges = contiguousRanges(boundaries, total, trimmed.length);
  return trimmed.map((text, i) => ({ text, sampleRange: ranges[i] }));
}
