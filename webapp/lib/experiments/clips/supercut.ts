import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

// Stitch helpers for `pnpm clip:supercut`. Footage is YouTube (drafts only
// store clip.wav + videoId in R2); the script downloads just the hit range
// with yt-dlp --download-sections and caches it.

export const SUPERCUT_DEFAULT_WIDTH = 1080;
export const SUPERCUT_DEFAULT_HEIGHT = 1920;
export const SUPERCUT_DEFAULT_FPS = 30;
export const SUPERCUT_DEFAULT_PAD = 0.8;
export const SUPERCUT_DEFAULT_LIMIT = 10;

export const FONT_CANDIDATES = [
  "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
  "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
  "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
  "/System/Library/Fonts/Hiragino Sans GB.ttc",
  "/Library/Fonts/Arial Unicode.ttf",
];

export type SupercutArgs = {
  word: string;
  level: number | null;
  feed: boolean;
  listed: boolean;
  limit: number;
  pad: number;
  out: string | null;
  burnIn: boolean;
  width: number;
  height: number;
  fps: number;
  cache: string;
  dryRun: boolean;
  studio: string | null;
};

export type SupercutHit = {
  clipId: string;
  videoId: string;
  lineIndex: number;
  lineText: string;
  matchedText: string;
  startSec: number;
  endSec: number;
  charStart?: number;
};

export type PaddedRange = { startSec: number; endSec: number };

export function paddedRange(startSec: number, endSec: number, pad: number, minStart = 0): PaddedRange {
  const start = Math.max(minStart, startSec - pad);
  const end = Math.max(start + 0.05, endSec + pad);
  return { startSec: round3(start), endSec: round3(end) };
}

export function cacheFileName(videoId: string, startSec: number, endSec: number): string {
  return `${videoId}_${startSec.toFixed(3)}-${endSec.toFixed(3)}.mp4`;
}

export function youtubeUrl(videoId: string): string {
  return `https://www.youtube.com/watch?v=${videoId}`;
}

export function sectionTime(seconds: number): string {
  return String(Number(seconds.toFixed(3)));
}

export function findFontPath(candidates: string[] = FONT_CANDIDATES): string | null {
  return candidates.find((p) => existsSync(p)) ?? null;
}

export function escapeAss(text: string): string {
  return text.replace(/\\/g, "\\\\").replace(/\{/g, "\\{").replace(/\}/g, "\\}");
}

/** Highlight `matchedText` in the line (first occurrence, or `charStart` if it lines up). */
export function highlightAss(lineText: string, matchedText: string, charStart?: number): string {
  let start = -1;
  if (charStart !== undefined && lineText.slice(charStart, charStart + matchedText.length) === matchedText) {
    start = charStart;
  } else {
    start = lineText.indexOf(matchedText);
  }
  if (start < 0) return escapeAss(lineText);
  return (
    escapeAss(lineText.slice(0, start)) +
    "{\\c&H00FFFF&}" +
    escapeAss(lineText.slice(start, start + matchedText.length)) +
    "{\\r}" +
    escapeAss(lineText.slice(start + matchedText.length))
  );
}

export function assDocument(opts: {
  width: number;
  height: number;
  lineText: string;
  matchedText: string;
  charStart?: number;
  fontName?: string;
}): string {
  const font = opts.fontName ?? "Sans";
  const dialogue = highlightAss(opts.lineText, opts.matchedText, opts.charStart);
  const fontSize = Math.max(36, Math.round(opts.height / 24));
  const margin = Math.round(opts.height / 24);
  return `[Script Info]
ScriptType: v4.00+
PlayResX: ${opts.width}
PlayResY: ${opts.height}
WrapStyle: 2

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,${font},${fontSize},&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,3,0,2,${margin},${margin},${margin},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,9:00:00.00,Default,,0,0,0,,{\\an2}${dialogue}
`;
}

const flag = (args: string[], name: string) => args.includes(name);
const option = (args: string[], name: string) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};

export function parseSupercutArgs(argv: string[]): SupercutArgs {
  const word = option(argv, "--word")?.trim();
  if (!word) throw new Error("Pass --word (e.g. --word ちゃう).");
  const levelRaw = option(argv, "--level");
  const level = levelRaw === undefined ? null : Number(levelRaw);
  if (level !== null && !(Number.isInteger(level) && level >= 1 && level <= 5)) {
    throw new Error("--level must be 1 (N1) to 5 (N5).");
  }
  const limitRaw = option(argv, "--limit");
  const limit = limitRaw === undefined ? SUPERCUT_DEFAULT_LIMIT : Number(limitRaw);
  if (!(Number.isInteger(limit) && limit >= 1 && limit <= 100)) {
    throw new Error("--limit must be 1 to 100.");
  }
  const padRaw = option(argv, "--pad");
  const pad = padRaw === undefined ? SUPERCUT_DEFAULT_PAD : Number(padRaw);
  if (!Number.isFinite(pad) || pad < 0 || pad > 10) {
    throw new Error("--pad must be 0 to 10 seconds.");
  }
  const width = Number(option(argv, "--width") ?? SUPERCUT_DEFAULT_WIDTH);
  const height = Number(option(argv, "--height") ?? SUPERCUT_DEFAULT_HEIGHT);
  const fps = Number(option(argv, "--fps") ?? SUPERCUT_DEFAULT_FPS);
  if (![width, height, fps].every((n) => Number.isFinite(n) && n > 0)) {
    throw new Error("--width, --height and --fps must be positive numbers.");
  }
  return {
    word,
    level,
    feed: flag(argv, "--feed"),
    listed: !flag(argv, "--all"),
    limit,
    pad,
    out: option(argv, "--out") ?? null,
    burnIn: flag(argv, "--burn-in"),
    width,
    height,
    fps,
    cache: option(argv, "--cache") ?? path.join(".cache", "clip-supercut"),
    dryRun: flag(argv, "--dry-run"),
    studio: option(argv, "--studio") ?? null,
  };
}

export function defaultOutPath(word: string): string {
  const safe = word.replace(/[^\p{L}\p{N}-]+/gu, "_").slice(0, 40) || "word";
  const stamp = new Date().toISOString().replace(/[:.]/g, "").slice(0, 15);
  return `supercut-${safe}-${stamp}.mp4`;
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}

export function runCommand(
  command: string,
  args: string[],
  opts?: { cwd?: string; inherit?: boolean }
): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn(command, args, {
      cwd: opts?.cwd,
      stdio: opts?.inherit ? "inherit" : ["ignore", "inherit", "pipe"],
    });
    let stderr = "";
    proc.stderr?.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    proc.on("error", reject);
    proc.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} failed (exit ${code}): ${stderr.slice(-2000) || "no output"}`));
    });
  });
}

export async function encodeSegment(opts: {
  ffmpeg: string;
  input: string;
  output: string;
  width: number;
  height: number;
  fps: number;
  burnIn: boolean;
  lineText?: string;
  matchedText?: string;
  charStart?: number;
  fontPath?: string | null;
}): Promise<void> {
  const vf = [
    `scale=${opts.width}:${opts.height}:force_original_aspect_ratio=decrease`,
    `pad=${opts.width}:${opts.height}:(ow-iw)/2:(oh-ih)/2`,
    `fps=${opts.fps}`,
    "format=yuv420p",
  ];
  const extra: string[] = [];
  if (opts.burnIn && opts.lineText && opts.matchedText) {
    const assPath = opts.output.replace(/\.mp4$/i, ".ass");
    await writeFile(
      assPath,
      assDocument({
        width: opts.width,
        height: opts.height,
        lineText: opts.lineText,
        matchedText: opts.matchedText,
        charStart: opts.charStart,
        fontName: opts.fontPath ? path.parse(opts.fontPath).name : "Sans",
      }),
      "utf8"
    );
    const fontsDir = opts.fontPath ? path.dirname(opts.fontPath) : undefined;
    const escaped = assPath.replace(/\\/g, "/").replace(/:/g, "\\:").replace(/,/g, "\\,");
    vf.push(fontsDir ? `subtitles=${escaped}:fontsdir=${fontsDir.replace(/:/g, "\\:")}` : `subtitles=${escaped}`);
  }
  extra.push(
    "-vf",
    vf.join(","),
    "-af",
    "loudnorm=I=-16:TP=-1.5:LRA=11",
    "-c:v",
    "libx264",
    "-preset",
    "fast",
    "-crf",
    "20",
    "-c:a",
    "aac",
    "-ar",
    "48000",
    "-ac",
    "2",
    "-movflags",
    "+faststart",
    "-y",
    opts.output
  );
  await runCommand(opts.ffmpeg, ["-hide_banner", "-loglevel", "error", "-i", opts.input, ...extra]);
}

export async function concatSegments(ffmpeg: string, segments: string[], outPath: string): Promise<void> {
  const dir = path.dirname(outPath);
  await mkdir(dir, { recursive: true });
  const listPath = outPath.replace(/\.mp4$/i, ".concat.txt");
  const body = segments.map((file) => `file '${file.replace(/'/g, "'\\''")}'`).join("\n");
  await writeFile(listPath, body, "utf8");
  await runCommand(ffmpeg, [
    "-hide_banner",
    "-loglevel",
    "error",
    "-f",
    "concat",
    "-safe",
    "0",
    "-i",
    listPath,
    "-c",
    "copy",
    "-movflags",
    "+faststart",
    "-y",
    outPath,
  ]);
}

export type LocalClip = {
  path: string;
  lineText: string;
  matchedText: string;
  charStart?: number;
};

/** Encode + concat already-local media (no YouTube). Used by the script and tests. */
export async function stitchLocalClips(opts: {
  ffmpeg: string;
  clips: LocalClip[];
  outPath: string;
  width: number;
  height: number;
  fps: number;
  burnIn: boolean;
  fontPath?: string | null;
  workDir: string;
}): Promise<void> {
  await mkdir(opts.workDir, { recursive: true });
  const segments: string[] = [];
  for (let i = 0; i < opts.clips.length; i++) {
    const clip = opts.clips[i]!;
    const output = path.join(opts.workDir, `seg-${String(i).padStart(3, "0")}.mp4`);
    await encodeSegment({
      ffmpeg: opts.ffmpeg,
      input: clip.path,
      output,
      width: opts.width,
      height: opts.height,
      fps: opts.fps,
      burnIn: opts.burnIn,
      lineText: clip.lineText,
      matchedText: clip.matchedText,
      charStart: clip.charStart,
      fontPath: opts.fontPath,
    });
    segments.push(output);
  }
  await concatSegments(opts.ffmpeg, segments, opts.outPath);
}
