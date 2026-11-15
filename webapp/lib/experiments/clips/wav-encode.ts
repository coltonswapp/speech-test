// Browser-only: cut [startSec, endSec) out of a local audio/video file and
// encode it as mono 16-bit PCM WAV at CLIP_SAMPLE_RATE. Doing this client-side
// keeps the upload small (~32 KB/s) and avoids sending whole videos to Vercel.

import { CLIP_SAMPLE_RATE } from "@/lib/experiments/clips/types";

/**
 * @param endSec null = to the end of the file (whole-video clips).
 * @param fileOffsetSec video time at the file's t=0 (0 when the file is the
 *   whole video; the clip start when the file is already just the clip).
 * @param maxDurationSec checked after decoding, for clips that run to the end.
 */
export async function cutClipToWav(
  file: File,
  startSec: number,
  endSec: number | null,
  fileOffsetSec = 0,
  maxDurationSec = Infinity
): Promise<{ wav: Blob; durationSec: number }> {
  const from = startSec - fileOffsetSec;
  if (from < 0) throw new Error("Clip starts before the file does; check the file offset.");
  if (endSec !== null && endSec <= startSec) throw new Error("End must be after start.");

  const decodeContext = new AudioContext();
  let decoded: AudioBuffer;
  try {
    decoded = await decodeContext.decodeAudioData(await file.arrayBuffer());
  } catch {
    throw new Error("The browser could not decode this file. Try an MP3, M4A, WAV or MP4.");
  } finally {
    void decodeContext.close();
  }
  // Rounded to ms so the stored end time matches what the payload reports.
  const duration =
    endSec !== null ? endSec - startSec : Math.floor((decoded.duration - from) * 1000) / 1000;
  if (duration <= 0) throw new Error("Clip starts after the file ends; check the file offset.");
  if (duration > maxDurationSec) {
    throw new Error(
      `This is ${duration.toFixed(1)} s; clips are limited to ${maxDurationSec} s for now. Set start and end times.`
    );
  }
  // Section downloads can come back a few frames short; the render pads any
  // shortfall with silence. More than that means the wrong file or offset.
  if (from + duration > decoded.duration + 0.5) {
    throw new Error(
      `File is ${decoded.duration.toFixed(1)} s long; the clip ends at ${(from + duration).toFixed(1)} s in the file.`
    );
  }

  const frames = Math.ceil(duration * CLIP_SAMPLE_RATE);
  const offline = new OfflineAudioContext(1, frames, CLIP_SAMPLE_RATE);
  const source = offline.createBufferSource();
  source.buffer = decoded;
  source.connect(offline.destination); // down-mixes to mono and resamples
  source.start(0, from, duration);
  const rendered = await offline.startRendering();
  return { wav: encodePcm16Wav(rendered.getChannelData(0), CLIP_SAMPLE_RATE), durationSec: duration };
}

/**
 * Decodes a whole local audio/video file to mono CLIP_SAMPLE_RATE samples, for
 * splitting a long video into clips. A 20-minute file is ~77 MB of samples.
 */
export async function decodeFileToMono(file: File): Promise<Float32Array> {
  const decodeContext = new AudioContext();
  let decoded: AudioBuffer;
  try {
    decoded = await decodeContext.decodeAudioData(await file.arrayBuffer());
  } catch {
    throw new Error("The browser could not decode this file. Try an MP3, M4A, WAV or MP4.");
  } finally {
    void decodeContext.close();
  }
  const frames = Math.ceil(decoded.duration * CLIP_SAMPLE_RATE);
  if (frames <= 0) throw new Error("This file has no audio.");
  const offline = new OfflineAudioContext(1, frames, CLIP_SAMPLE_RATE);
  const source = offline.createBufferSource();
  source.buffer = decoded;
  source.connect(offline.destination); // down-mixes to mono and resamples
  source.start(0);
  return (await offline.startRendering()).getChannelData(0);
}

/** WAV for `[startSec, endSec)` of samples from decodeFileToMono. */
export function encodeSamplesToWav(samples: Float32Array, startSec: number, endSec: number): Blob {
  const from = Math.max(0, Math.round(startSec * CLIP_SAMPLE_RATE));
  const to = Math.min(samples.length, Math.round(endSec * CLIP_SAMPLE_RATE));
  return encodePcm16Wav(samples.subarray(from, to), CLIP_SAMPLE_RATE);
}

function encodePcm16Wav(samples: Float32Array, sampleRate: number): Blob {
  const dataBytes = samples.length * 2;
  const buffer = new ArrayBuffer(44 + dataBytes);
  const view = new DataView(buffer);
  const writeAscii = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) view.setUint8(offset + i, text.charCodeAt(i));
  };
  writeAscii(0, "RIFF");
  view.setUint32(4, 36 + dataBytes, true);
  writeAscii(8, "WAVE");
  writeAscii(12, "fmt ");
  view.setUint32(16, 16, true); // fmt chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); // byte rate
  view.setUint16(32, 2, true); // block align
  view.setUint16(34, 16, true); // bits per sample
  writeAscii(36, "data");
  view.setUint32(40, dataBytes, true);
  let offset = 44;
  for (let i = 0; i < samples.length; i++, offset += 2) {
    const s = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7fff, true);
  }
  return new Blob([buffer], { type: "audio/wav" });
}
