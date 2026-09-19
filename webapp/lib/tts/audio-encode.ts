import "server-only";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import ffmpegPath from "@ffmpeg-installer/ffmpeg";
import {
  AMBIENCE_FADE_SECONDS,
  ambienceMixFilterComplex,
} from "@/lib/tts/ambience";

// Port of TrimmedAudioExport+MP3.swift / +M4A.swift — the Swift app shells out
// conceptually to the same encoders (it notes Apple exposes no system MP3
// encoder and uses FFmpeg itself for MP3; AAC/M4A goes through AVFoundation
// natively there, but the ffmpeg path here produces an equivalent M4A with
// the same custom metadata comment tag).

export const DIALOGUE_METADATA_PREFIX = "shizen.dialogue.v1:";

function runFfmpeg(args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn(ffmpegPath.path, args);
    let stderr = "";
    proc.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    proc.on("error", reject);
    proc.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`ffmpeg exited with code ${code}: ${stderr.slice(-2000)}`));
      }
    });
  });
}

async function withTempDir<T>(fn: (dir: string) => Promise<T>): Promise<T> {
  const dir = await mkdtemp(path.join(tmpdir(), "shizen-encode-"));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

export async function encodeWavToMp3(wav: Buffer): Promise<Buffer> {
  return withTempDir(async (dir) => {
    const inPath = path.join(dir, "in.wav");
    const outPath = path.join(dir, "out.mp3");
    await writeFile(inPath, wav);
    await runFfmpeg(["-i", inPath, "-codec:a", "libmp3lame", "-qscale:a", "2", "-y", outPath]);
    return readFile(outPath);
  });
}

export async function encodeWavToM4a(
  wav: Buffer,
  lineSwitchSeconds: number[] = []
): Promise<Buffer> {
  return encodeAudioToM4a(wav, lineSwitchSeconds);
}

/** AAC m4a for any ffmpeg-readable input (WAV take or library bed). */
export async function encodeAudioToM4a(
  audio: Buffer,
  lineSwitchSeconds: number[] = []
): Promise<Buffer> {
  return withTempDir(async (dir) => {
    const inPath = path.join(dir, "in.bin");
    const outPath = path.join(dir, "out.m4a");
    await writeFile(inPath, audio);

    const args = ["-i", inPath, "-codec:a", "aac", "-b:a", "128k"];
    if (lineSwitchSeconds.length > 0) {
      const payload = `${DIALOGUE_METADATA_PREFIX}${JSON.stringify({
        version: 1,
        lineSwitchSeconds,
      })}`;
      args.push("-metadata", `comment=${payload}`);
    }
    args.push("-y", outPath);

    await runFfmpeg(args);
    return readFile(outPath);
  });
}

export type AmbienceMixOptions = {
  bed: Buffer;
  gainDb: number;
  offsetSeconds: number;
  startSeconds?: number;
  endSeconds?: number | null;
  duck?: boolean;
};

/**
 * Mix one or more loopable ambience beds under a dry dialogue WAV. Output is
 * the same length as the dialogue clip (t=0 speech alignment preserved for karaoke).
 */
export async function mixDialogueWithAmbienceBed(
  dialogueWav: Buffer,
  mix: AmbienceMixOptions | AmbienceMixOptions[]
): Promise<Buffer> {
  const layers = Array.isArray(mix) ? mix : [mix];
  if (layers.length === 0) return dialogueWav;
  const duration = wavDurationSeconds(dialogueWav);
  const graph = ambienceMixFilterComplex({
    durationSeconds: duration,
    gainDb: layers[0].gainDb,
    offsetSeconds: layers[0].offsetSeconds,
    fadeSeconds: AMBIENCE_FADE_SECONDS,
    duck: layers[0].duck,
    layers: layers.map((layer) => ({
      gainDb: layer.gainDb,
      offsetSeconds: layer.offsetSeconds,
      startSeconds: layer.startSeconds ?? 0,
      endSeconds: layer.endSeconds ?? null,
    })),
  });

  return withTempDir(async (dir) => {
    const dialoguePath = path.join(dir, "dialogue.wav");
    const outPath = path.join(dir, "mixed.wav");
    await writeFile(dialoguePath, dialogueWav);
    const args = ["-i", dialoguePath];
    for (let i = 0; i < layers.length; i++) {
      const bedPath = path.join(dir, `bed-${i}.bin`);
      await writeFile(bedPath, layers[i].bed);
      args.push("-stream_loop", "-1", "-i", bedPath);
    }
    args.push(
      "-filter_complex",
      graph,
      "-map",
      "[out]",
      "-t",
      duration.toFixed(4),
      "-y",
      outPath
    );
    await runFfmpeg(args);
    return readFile(outPath);
  });
}

export async function probeAudioMetadata(audio: Buffer): Promise<{
  durationSeconds: number;
  sampleRate: number | null;
}> {
  return withTempDir(async (dir) => {
    const inPath = path.join(dir, "in.bin");
    await writeFile(inPath, audio);
    const stderr = await ffmpegInfo(inPath);
    const durationMatch = /Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/.exec(stderr);
    if (!durationMatch) {
      throw new Error("Could not read audio duration. Use a WAV, MP3, or M4A loop.");
    }
    const durationSeconds =
      Number(durationMatch[1]) * 3600 +
      Number(durationMatch[2]) * 60 +
      Number(durationMatch[3]);
    if (!Number.isFinite(durationSeconds) || durationSeconds < 0.5) {
      throw new Error("Ambience bed must be at least 0.5 seconds long.");
    }
    const rateMatch = /(\d+)\s*Hz/.exec(stderr);
    return {
      durationSeconds,
      sampleRate: rateMatch ? Number(rateMatch[1]) : null,
    };
  });
}

function wavDurationSeconds(wav: Buffer): number {
  if (wav.length < 44) return 0;
  const sampleRate = wav.readUInt32LE(24);
  const byteRate = wav.readUInt32LE(28);
  if (sampleRate <= 0 || byteRate <= 0) return 0;
  const dataSize = Math.max(0, wav.length - 44);
  return dataSize / byteRate;
}

function ffmpegInfo(inPath: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const proc = spawn(ffmpegPath.path, ["-i", inPath]);
    let stderr = "";
    proc.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    proc.on("error", reject);
    proc.on("close", () => resolve(stderr));
  });
}

/** Reads back the embedded dialogue line-switch metadata from an M4A, if present. */
export async function readM4aLineSwitchSeconds(
  m4a: Buffer
): Promise<number[] | null> {
  return withTempDir(async (dir) => {
    const inPath = path.join(dir, "in.m4a");
    await writeFile(inPath, m4a);

    const output = await new Promise<string>((resolve, reject) => {
      const proc = spawn(ffmpegPath.path, ["-i", inPath]);
      let stderr = "";
      proc.stderr.on("data", (chunk) => {
        stderr += chunk.toString();
      });
      proc.on("error", reject);
      // ffmpeg -i with no output always "fails" (no output file given) —
      // its stream/metadata info is on stderr regardless of exit code.
      proc.on("close", () => resolve(stderr));
    });

    const match = /comment\s*:\s*(shizen\.dialogue\.v1:.*)/.exec(output);
    if (!match) return null;
    const jsonText = match[1].slice(DIALOGUE_METADATA_PREFIX.length).trim();
    try {
      const parsed = JSON.parse(jsonText);
      return Array.isArray(parsed.lineSwitchSeconds)
        ? parsed.lineSwitchSeconds
        : null;
    } catch {
      return null;
    }
  });
}
