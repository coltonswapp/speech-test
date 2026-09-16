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

/**
 * Media-timeline seconds the listener is hearing — shared by line-switch Mark
 * and karaoke token stamp (via the waveform `onGetPlayhead` hook).
 *
 * While playing, subtracts wall-clock output latency scaled into media time.
 * Pass `wallLatencySeconds: 0` on the Apple-touch native `<audio>` path (no
 * MediaElementSource / Web Audio graph), so Mark, the cursor, and the audible
 * beat share one clock.
 *
 * When paused or scrubbed, returns `mediaCurrentTime` unchanged — the playhead
 * is exactly where the user put it.
 *
 * Does **not** apply human tap lookback. Token stamps add
 * `TOKEN_STAMP_LOOKBACK_SECONDS` separately in `proposedStampSeconds` after
 * this heard time is sampled; line Marks do not (deliberate, fewer taps).
 */
export function stampMediaTimeNow(params: {
  mediaCurrentTime: number;
  isPlaying: boolean;
  playbackRate: number;
  /** Wall-clock Web Audio + hardware latency; 0 when not routed through Web Audio. */
  wallLatencySeconds: number;
}): number {
  const { mediaCurrentTime, isPlaying, playbackRate, wallLatencySeconds } =
    params;
  if (!Number.isFinite(mediaCurrentTime)) return 0;
  const clamped = Math.max(0, mediaCurrentTime);
  if (!isPlaying) return clamped;
  const latencyMedia = wallDelayToMediaSeconds(
    wallLatencySeconds,
    playbackRate
  );
  return Math.max(0, clamped - latencyMedia);
}
