/**
 * Convert a wall-clock delay into media-timeline seconds at `playbackRate`.
 *
 * AudioContext `baseLatency` / `outputLatency` and human tap lag are wall-clock.
 * `HTMLMediaElement.currentTime` advances in media time (`playbackRate` media
 * seconds per wall second), so the audible media position trails `currentTime`
 * by `wallSeconds * playbackRate` — not by the raw wall value.
 *
 * Subtracting the unscaled wall delay from media time at 0.5× over-subtracts
 * (double-counts relative to 1×) and pulls marks/stamps early on the clip.
 * The return value is already media-timeline seconds: apply it directly to
 * `currentTime` with no further rate scaling.
 */
export function wallDelayToMediaSeconds(
  wallSeconds: number,
  playbackRate: number
): number {
  if (!Number.isFinite(wallSeconds) || wallSeconds <= 0) return 0;
  const rate =
    Number.isFinite(playbackRate) && playbackRate > 0 ? playbackRate : 1;
  return wallSeconds * rate;
}
