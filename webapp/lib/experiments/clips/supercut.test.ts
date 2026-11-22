import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, it } from "node:test";
import {
  assDocument,
  cacheFileName,
  findFontPath,
  highlightAss,
  paddedRange,
  parseSupercutArgs,
  stitchLocalClips,
} from "./supercut";

function run(command: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn(command, args);
    let stderr = "";
    proc.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    proc.on("error", reject);
    proc.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} ${code}: ${stderr.slice(-500)}`));
    });
  });
}

describe("supercut helpers", () => {
  it("pads a hit and names the cache file from video time", () => {
    assert.deepEqual(paddedRange(12.4, 13.1, 0.8), { startSec: 11.6, endSec: 13.9 });
    assert.deepEqual(paddedRange(0.2, 0.5, 0.8), { startSec: 0, endSec: 1.3 });
    assert.equal(cacheFileName("abcdefghijk", 11.6, 13.9), "abcdefghijk_11.600-13.900.mp4");
  });

  it("highlights the matched word in ASS (and escapes braces)", () => {
    assert.equal(highlightAss("行っちゃう？", "ちゃう"), "行っ{\\c&H00FFFF&}ちゃう{\\r}？");
    assert.equal(highlightAss("a{b}c", "b"), "a\\{{\\c&H00FFFF&}b{\\r}\\}c");
    const doc = assDocument({
      width: 1080,
      height: 1920,
      lineText: "しています",
      matchedText: "ています",
    });
    assert.match(doc, /{\\c&H00FFFF&}ています{\\r}/);
  });

  it("parses CLI flags", () => {
    const args = parseSupercutArgs(["--word", "ちゃう", "--limit", "3", "--pad", "0.5", "--feed", "--burn-in"]);
    assert.equal(args.word, "ちゃう");
    assert.equal(args.limit, 3);
    assert.equal(args.pad, 0.5);
    assert.equal(args.feed, true);
    assert.equal(args.burnIn, true);
    assert.equal(args.listed, true);
    assert.throws(() => parseSupercutArgs([]), /--word/);
  });
});

describe("supercut stitch (local ffmpeg, no YouTube)", () => {
  it("normalizes two short clips and concatenates them", async () => {
    const dir = await mkdtemp(path.join(tmpdir(), "supercut-"));
    try {
      const a = path.join(dir, "a.mp4");
      const b = path.join(dir, "b.mp4");
      const out = path.join(dir, "out.mp4");
      const make = (file: string, color: string) =>
        run("ffmpeg", [
          "-hide_banner",
          "-loglevel",
          "error",
          "-f",
          "lavfi",
          "-i",
          `color=c=${color}:s=320x240:d=0.4:r=24`,
          "-f",
          "lavfi",
          "-i",
          "sine=frequency=440:duration=0.4",
          "-shortest",
          "-pix_fmt",
          "yuv420p",
          "-y",
          file,
        ]);
      await make(a, "red");
      await make(b, "blue");
      await stitchLocalClips({
        ffmpeg: "ffmpeg",
        clips: [
          { path: a, lineText: "しています", matchedText: "ています" },
          { path: b, lineText: "行っちゃう", matchedText: "ちゃう" },
        ],
        outPath: out,
        width: 320,
        height: 560,
        fps: 30,
        burnIn: Boolean(findFontPath()),
        fontPath: findFontPath(),
        workDir: path.join(dir, "work"),
      });
      const info = await stat(out);
      assert.ok(info.size > 1000, `expected a real mp4, got ${info.size} bytes`);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
