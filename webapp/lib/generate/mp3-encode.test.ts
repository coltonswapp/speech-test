import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, it } from "node:test";
import ffmpegPath from "@ffmpeg-installer/ffmpeg";
import { pcm16ToWav } from "../tts/wav";
import { isMpegAudio, silencePcm16 } from "./compose";

function runFfmpeg(args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn(ffmpegPath.path, args);
    let stderr = "";
    proc.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    proc.on("error", reject);
    proc.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`ffmpeg ${code}: ${stderr.slice(-500)}`));
    });
  });
}

describe("combined MP3 encoding (local ffmpeg, no Gemini)", () => {
  it("encodes concatenated PCM to MPEG audio, not a renamed WAV", async () => {
    const wav = pcm16ToWav(
      Buffer.concat([silencePcm16(24_000, 0.2), silencePcm16(24_000, 0.1)]),
      24_000,
    );
    const dir = await mkdtemp(path.join(tmpdir(), "generate-mp3-"));
    try {
      const inPath = path.join(dir, "in.wav");
      const outPath = path.join(dir, "out.mp3");
      await writeFile(inPath, wav);
      await runFfmpeg([
        "-i",
        inPath,
        "-codec:a",
        "libmp3lame",
        "-qscale:a",
        "2",
        "-y",
        outPath,
      ]);
      const mp3 = await readFile(outPath);
      assert.equal(isMpegAudio(mp3), true);
      assert.notEqual(mp3.subarray(0, 4).toString("ascii"), "RIFF");
      assert.ok(mp3.length > 32);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
