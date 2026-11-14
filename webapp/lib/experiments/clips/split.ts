// Cut a long recording into clip-sized pieces at pauses. Pure (no DOM), so it
// runs in the browser on the decoded audio before anything is uploaded.

export type ClipSegment = {
  /** Seconds from the start of `samples`. */
  startSec: number;
  endSec: number;
};

const FRAME_SECONDS = 0.02;
/** A cut needs about this much quiet around it. */
const PAUSE_SECONDS = 0.3;

/**
 * Splits `samples` into consecutive pieces of about `targetSec` each, ending
 * every piece in the quietest pause near that length (speakers pause between
 * sentences, so cuts rarely land mid-word). Pieces are back to back and cover
 * the whole recording: one piece's end is the next one's start. Each is
 * between half of `targetSec` and `maxSec` long, except that a recording
 * shorter than that comes back as a single piece.
 */
export function splitAtPauses(
  samples: Float32Array,
  sampleRate: number,
  targetSec: number,
  maxSec: number
): ClipSegment[] {
  const totalSec = samples.length / sampleRate;
  if (totalSec <= 0) return [];
  const target = Math.min(targetSec, maxSec);
  const shortest = target / 2;
  const longest = Math.min(maxSec, target * 1.5);

  // Mean square per 20 ms frame, then prefix sums for windowed averages.
  const frameSize = Math.max(1, Math.round(sampleRate * FRAME_SECONDS));
  const frameCount = Math.ceil(samples.length / frameSize);
  const prefix = new Float64Array(frameCount + 1);
  for (let f = 0; f < frameCount; f++) {
    const from = f * frameSize;
    const to = Math.min(samples.length, from + frameSize);
    let sum = 0;
    for (let i = from; i < to; i++) sum += samples[i] * samples[i];
    prefix[f + 1] = prefix[f] + sum / (to - from);
  }
  const overall = prefix[frameCount] / frameCount;
  // Keeps digital silence from tying everywhere, so distance to target decides.
  const floor = overall * 0.001 + 1e-9;
  const half = Math.max(1, Math.round(PAUSE_SECONDS / FRAME_SECONDS / 2));
  const loudnessAround = (frame: number) => {
    const a = Math.max(0, frame - half);
    const b = Math.min(frameCount, frame + half);
    return (prefix[b] - prefix[a]) / (b - a);
  };
  const frameOf = (seconds: number) => Math.round(seconds / FRAME_SECONDS);
  const round3 = (n: number) => Math.round(n * 1000) / 1000;

  const segments: ClipSegment[] = [];
  let cursor = 0;
  while (totalSec - cursor > longest) {
    // Leave at least `shortest` for the piece after this one.
    const lo = frameOf(cursor + shortest);
    const hi = frameOf(Math.min(cursor + longest, totalSec - shortest));
    const want = frameOf(cursor + target);
    let best = Math.min(Math.max(want, lo), hi);
    let bestScore = Infinity;
    for (let f = lo; f <= hi; f++) {
      // Quietest wins; among similar pauses, the one nearest the target length.
      const score = (loudnessAround(f) + floor) * (1 + Math.abs(f - want) / (want - frameOf(cursor)));
      if (score < bestScore) {
        bestScore = score;
        best = f;
      }
    }
    const cut = round3(best * FRAME_SECONDS);
    segments.push({ startSec: cursor, endSec: cut });
    cursor = cut;
  }
  segments.push({ startSec: cursor, endSec: Math.floor(totalSec * 1000) / 1000 });
  return segments;
}

/** `lions` + piece 3 of 12 → `lions-03` (zero-padded to the count's width, at least 2). */
export function splitClipId(prefix: string, index: number, count: number): string {
  const width = Math.max(2, String(count).length);
  return `${prefix}-${String(index + 1).padStart(width, "0")}`;
}
