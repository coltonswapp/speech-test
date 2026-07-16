import "server-only";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import ffmpegPath from "@ffmpeg-installer/ffmpeg";

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
  return withTempDir(async (dir) => {
    const inPath = path.join(dir, "in.wav");
    const outPath = path.join(dir, "out.m4a");
    await writeFile(inPath, wav);

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
