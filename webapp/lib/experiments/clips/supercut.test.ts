import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, it } from "node:test";
import { readFile } from "node:fs/promises";
import {
  assDocument,
  BURN_IN_FILTERS_MISSING,
  buildSegmentManifest,
  cacheFileName,
  findFontPath,
  highlightAss,
  paddedRange,
  parseFfmpegFilterNames,
  parseSupercutArgs,
  pickBurnInBackend,
  quoteFilterArg,
  segmentFileName,
  stitchLocalClips,
  subtitlesFilter,
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
    const args = parseSupercutArgs([
      "--word",
      "ちゃう",
      "--limit",
      "3",
      "--pad",
      "0.5",
      "--feed",
      "--burn-in",
      "--segments-dir",
      "/tmp/chau-clips",
      "--no-concat",
    ]);
    assert.equal(args.word, "ちゃう");
    assert.equal(args.limit, 3);
    assert.equal(args.pad, 0.5);
    assert.equal(args.feed, true);
    assert.equal(args.burnIn, true);
    assert.equal(args.listed, true);
    assert.equal(args.segmentsDir, "/tmp/chau-clips");
    assert.equal(args.noConcat, true);
    assert.throws(() => parseSupercutArgs([]), /--word/);
    assert.throws(() => parseSupercutArgs(["--word", "ちゃう", "--no-concat"]), /--segments-dir/);
  });

  it("quotes subtitles filter paths so : is not an option separator", () => {
    assert.equal(quoteFilterArg("it's"), "'it\\'s'");
    assert.equal(
      subtitlesFilter("/private/tmp/work/seg-000.ass", "/System/Library/Fonts"),
      "subtitles=filename='/private/tmp/work/seg-000.ass':fontsdir='/System/Library/Fonts'"
    );
  });

  it("prefers drawtext when ffmpeg has no libass", () => {
    const names = parseFfmpegFilterNames(`
 TSC allpass           A->A       Apply a two-pole all-pass filter.
 T.C drawtext          V->V       Draw text on top of video frames
 ... subtitles         V->V       Render text subtitles onto input video
 ... ass               V->V       Render ASS subtitles onto input video
`);
    assert.equal(pickBurnInBackend(names), "drawtext");
    assert.equal(pickBurnInBackend(new Set(["subtitles"])), "subtitles");
    assert.equal(pickBurnInBackend(new Set(["ass"])), "subtitles");
    assert.equal(pickBurnInBackend(new Set(["scale"])), null);
    assert.match(BURN_IN_FILTERS_MISSING, /libass/);
  });

  it("names per-hit files and builds a Remotion-ready manifest", () => {
    const file = segmentFileName(0, {
      clipId: "short-a9rdrqftny0",
      lineIndex: 8,
      matchedText: "ちゃう",
    });
    assert.equal(file, "01_short-a9rdrqftny0_l8_ちゃう.mp4");
    const manifest = buildSegmentManifest({
      word: "ちゃう",
      pad: 0.8,
      width: 1080,
      height: 1920,
      fps: 30,
      burnIn: false,
      createdAt: "2026-11-22T00:00:00.000Z",
      files: [file],
      clips: [
        {
          path: "/tmp/cached.mp4",
          clipId: "short-a9rdrqftny0",
          videoId: "a9rdrqftny0",
          lineIndex: 8,
          lineText: "行っちゃう？",
          matchedText: "ちゃう",
          startSec: 12.4,
          endSec: 13.1,
          paddedStartSec: 11.6,
          paddedEndSec: 13.9,
        },
      ],
    });
    assert.deepEqual(manifest.segments[0], {
      index: 1,
      file,
      clipId: "short-a9rdrqftny0",
      videoId: "a9rdrqftny0",
      lineIndex: 8,
      lineText: "行っちゃう？",
      matchedText: "ちゃう",
      startSec: 12.4,
      endSec: 13.1,
      paddedStartSec: 11.6,
      paddedEndSec: 13.9,
    });
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
      const clips = [
        {
          path: a,
          lineText: "しています",
          matchedText: "ています",
          clipId: "short-aaa",
          videoId: "aaa",
          lineIndex: 1,
          startSec: 1,
          endSec: 1.4,
          paddedStartSec: 0.2,
          paddedEndSec: 2.2,
        },
        {
          path: b,
          lineText: "行っちゃう",
          matchedText: "ちゃう",
          clipId: "short-a9rdrqftny0",
          videoId: "a9rdrqftny0",
          lineIndex: 8,
          startSec: 12.4,
          endSec: 13.1,
          paddedStartSec: 11.6,
          paddedEndSec: 13.9,
        },
      ];
      await stitchLocalClips({
        ffmpeg: "ffmpeg",
        clips,
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

      const segmentsDir = path.join(dir, "segments");
      const result = await stitchLocalClips({
        ffmpeg: "ffmpeg",
        clips,
        outPath: null,
        segmentsDir,
        word: "ちゃう",
        pad: 0.8,
        width: 320,
        height: 560,
        fps: 30,
        burnIn: false,
        fontPath: null,
        workDir: path.join(dir, "work-seg"),
      });
      assert.equal(result.outPath, null);
      assert.equal(result.segmentFiles[1], "02_short-a9rdrqftny0_l8_ちゃう.mp4");
      const named = await stat(path.join(segmentsDir, result.segmentFiles[1]!));
      assert.ok(named.size > 1000);
      const manifest = JSON.parse(await readFile(result.manifestPath!, "utf8")) as {
        word: string;
        segments: { file: string; clipId: string; paddedStartSec: number }[];
      };
      assert.equal(manifest.word, "ちゃう");
      assert.equal(manifest.segments[1]?.clipId, "short-a9rdrqftny0");
      assert.equal(manifest.segments[1]?.paddedStartSec, 11.6);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
