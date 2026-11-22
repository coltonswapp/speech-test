import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, writeFile } from "node:fs/promises";
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
  segmentsDir: string | null;
  noConcat: boolean;
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

export type LocalClip = {
  path: string;
  lineText: string;
  matchedText: string;
  charStart?: number;
  clipId?: string;
  videoId?: string;
  lineIndex?: number;
  startSec?: number;
  endSec?: number;
  paddedStartSec?: number;
  paddedEndSec?: number;
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

export type BurnInBackend = "drawtext" | "subtitles";

export const BURN_IN_FILTERS_MISSING =
  "This ffmpeg has no drawtext or subtitles/ass filter, so --burn-in cannot run. Homebrew’s default ffmpeg is often built without libass (no subtitles/ass). This script prefers drawtext, which stock Homebrew ffmpeg usually includes. Install ffmpeg with libfreetype (drawtext) or a libass-enabled build (`brew tap homebrew-ffmpeg/ffmpeg && brew install homebrew-ffmpeg/ffmpeg/ffmpeg --with-libass`). Or omit --burn-in.";

const FILTER_NAME_LINE = /^\s*[.TSC]{3}\s+(\S+)\s+/;
const ffmpegFiltersCache = new Map<string, Promise<Set<string>>>();

/** Parse `ffmpeg -filters` stdout into filter names. */
export function parseFfmpegFilterNames(filtersOutput: string): Set<string> {
  const names = new Set<string>();
  for (const line of filtersOutput.split("\n")) {
    const match = line.match(FILTER_NAME_LINE);
    if (match) names.add(match[1]!);
  }
  return names;
}

export function pickBurnInBackend(filters: Set<string>): BurnInBackend | null {
  if (filters.has("drawtext")) return "drawtext";
  if (filters.has("subtitles") || filters.has("ass")) return "subtitles";
  return null;
}

export async function ffmpegFilterNames(ffmpeg: string): Promise<Set<string>> {
  let pending = ffmpegFiltersCache.get(ffmpeg);
  if (!pending) {
    pending = runCommandCapture(ffmpeg, ["-hide_banner", "-filters"]).then(parseFfmpegFilterNames);
    ffmpegFiltersCache.set(ffmpeg, pending);
  }
  return pending;
}

export async function resolveBurnInBackend(ffmpeg: string): Promise<BurnInBackend> {
  const backend = pickBurnInBackend(await ffmpegFilterNames(ffmpeg));
  if (!backend) throw new Error(BURN_IN_FILTERS_MISSING);
  return backend;
}

/**
 * Quote a filter option value so paths like `/private/tmp/seg-000.ass` and
 * `/System/Library/Fonts` are not split on `:`.
 */
export function quoteFilterArg(value: string): string {
  return `'${value.replace(/\\/g, "\\\\").replace(/'/g, "\\'")}'`;
}

function quoteFilterPath(value: string): string {
  return quoteFilterArg(value.replace(/\\/g, "/"));
}

export function subtitlesFilter(assPath: string, fontsDir?: string): string {
  const parts = [`subtitles=filename=${quoteFilterPath(assPath)}`];
  if (fontsDir) parts.push(`fontsdir=${quoteFilterPath(fontsDir)}`);
  return parts.join(":");
}

export function drawtextBurnInFilters(opts: {
  lineText: string;
  matchedText: string;
  height: number;
  fontPath?: string | null;
}): string[] {
  const fontSize = Math.max(36, Math.round(opts.height / 24));
  const margin = Math.round(opts.height / 24);
  const fontfile = opts.fontPath ? `:fontfile=${quoteFilterPath(opts.fontPath)}` : "";
  const common =
    `${fontfile}:fontsize=${fontSize}:borderw=4:bordercolor=black:box=1:boxborderw=12:boxcolor=black@0.55:expansion=none:fix_bounds=1`;
  const lineY = `h-text_h-${margin}`;
  const line = `drawtext=text=${quoteFilterArg(opts.lineText)}${common}:fontcolor=white:x=(w-text_w)/2:y=${lineY}`;
  if (!opts.matchedText || opts.matchedText === opts.lineText) return [line];
  const matchY = `h-text_h-${margin + fontSize + Math.round(margin * 0.35)}`;
  const match = `drawtext=text=${quoteFilterArg(opts.matchedText)}${common}:fontcolor=yellow:x=(w-text_w)/2:y=${matchY}`;
  return [match, line];
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
  const result: SupercutArgs = {
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
    segmentsDir: option(argv, "--segments-dir")?.trim() || null,
    noConcat: flag(argv, "--no-concat"),
  };
  if (flag(argv, "--segments-dir") && (!result.segmentsDir || result.segmentsDir.startsWith("--"))) {
    throw new Error("Pass --segments-dir <dir>.");
  }
  if (result.noConcat && !result.segmentsDir) {
    throw new Error("Pass --segments-dir <dir> when using --no-concat.");
  }
  return result;
}

export function defaultOutPath(word: string): string {
  const safe = safeFileToken(word, 40) || "word";
  const stamp = new Date().toISOString().replace(/[:.]/g, "").slice(0, 15);
  return `supercut-${safe}-${stamp}.mp4`;
}

export function safeFileToken(text: string, max = 40): string {
  return text.replace(/[^\p{L}\p{N}-]+/gu, "_").replace(/_+/g, "_").replace(/^_|_$/g, "").slice(0, max);
}

/** Ordered per-hit filename, e.g. `01_short-a9rdrqftny0_l8_ちゃう.mp4`. */
export function segmentFileName(index: number, clip: Pick<LocalClip, "clipId" | "lineIndex" | "matchedText">): string {
  const n = String(index + 1).padStart(2, "0");
  const id = safeFileToken(clip.clipId ?? "clip", 64) || "clip";
  const word = safeFileToken(clip.matchedText, 40) || "word";
  const line = Number.isInteger(clip.lineIndex) ? `_l${clip.lineIndex}` : "";
  return `${n}_${id}${line}_${word}.mp4`;
}

export type SegmentManifestEntry = {
  index: number;
  file: string;
  clipId: string;
  videoId: string;
  lineIndex: number;
  lineText: string;
  matchedText: string;
  startSec: number;
  endSec: number;
  paddedStartSec: number;
  paddedEndSec: number;
};

export type SegmentManifest = {
  word: string;
  pad: number;
  width: number;
  height: number;
  fps: number;
  burnIn: boolean;
  createdAt: string;
  segments: SegmentManifestEntry[];
};

export function buildSegmentManifest(opts: {
  word: string;
  pad: number;
  width: number;
  height: number;
  fps: number;
  burnIn: boolean;
  clips: LocalClip[];
  files: string[];
  createdAt?: string;
}): SegmentManifest {
  return {
    word: opts.word,
    pad: opts.pad,
    width: opts.width,
    height: opts.height,
    fps: opts.fps,
    burnIn: opts.burnIn,
    createdAt: opts.createdAt ?? new Date().toISOString(),
    segments: opts.clips.map((clip, i) => ({
      index: i + 1,
      file: opts.files[i] ?? segmentFileName(i, clip),
      clipId: clip.clipId ?? "",
      videoId: clip.videoId ?? "",
      lineIndex: clip.lineIndex ?? 0,
      lineText: clip.lineText,
      matchedText: clip.matchedText,
      startSec: clip.startSec ?? 0,
      endSec: clip.endSec ?? 0,
      paddedStartSec: clip.paddedStartSec ?? clip.startSec ?? 0,
      paddedEndSec: clip.paddedEndSec ?? clip.endSec ?? 0,
    })),
  };
}

export async function writeNamedSegments(opts: {
  segments: string[];
  clips: LocalClip[];
  dir: string;
  word: string;
  pad: number;
  width: number;
  height: number;
  fps: number;
  burnIn: boolean;
}): Promise<{ files: string[]; manifestPath: string }> {
  await mkdir(opts.dir, { recursive: true });
  const files: string[] = [];
  for (let i = 0; i < opts.segments.length; i++) {
    const src = opts.segments[i]!;
    const clip = opts.clips[i]!;
    const name = segmentFileName(i, clip);
    await copyFile(src, path.join(opts.dir, name));
    files.push(name);
  }
  const manifestPath = path.join(opts.dir, "manifest.json");
  await writeFile(
    manifestPath,
    `${JSON.stringify(buildSegmentManifest({ ...opts, files }), null, 2)}\n`,
    "utf8"
  );
  return { files, manifestPath };
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

export function runCommandCapture(command: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const proc = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    proc.stdout?.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    proc.stderr?.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    proc.on("error", reject);
    proc.on("close", (code) => {
      if (code === 0) resolve(stdout);
      else reject(new Error(`${command} failed (exit ${code}): ${(stderr || stdout).slice(-2000) || "no output"}`));
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
  burnInBackend?: BurnInBackend;
}): Promise<void> {
  const vf = [
    `scale=${opts.width}:${opts.height}:force_original_aspect_ratio=decrease`,
    `pad=${opts.width}:${opts.height}:(ow-iw)/2:(oh-ih)/2`,
    `fps=${opts.fps}`,
    "format=yuv420p",
  ];
  const extra: string[] = [];
  if (opts.burnIn && opts.lineText && opts.matchedText) {
    const backend = opts.burnInBackend ?? (await resolveBurnInBackend(opts.ffmpeg));
    if (backend === "drawtext") {
      vf.push(
        ...drawtextBurnInFilters({
          lineText: opts.lineText,
          matchedText: opts.matchedText,
          height: opts.height,
          fontPath: opts.fontPath,
        })
      );
    } else {
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
      vf.push(subtitlesFilter(assPath, fontsDir));
    }
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

export type StitchResult = {
  outPath: string | null;
  segmentFiles: string[];
  manifestPath: string | null;
};

/** Encode + concat already-local media (no YouTube). Used by the script and tests. */
export async function stitchLocalClips(opts: {
  ffmpeg: string;
  clips: LocalClip[];
  outPath?: string | null;
  segmentsDir?: string | null;
  word?: string;
  pad?: number;
  width: number;
  height: number;
  fps: number;
  burnIn: boolean;
  fontPath?: string | null;
  workDir: string;
}): Promise<StitchResult> {
  const concat = Boolean(opts.outPath);
  if (!concat && !opts.segmentsDir) {
    throw new Error("Pass --out or --segments-dir.");
  }
  await mkdir(opts.workDir, { recursive: true });
  const burnInBackend = opts.burnIn ? await resolveBurnInBackend(opts.ffmpeg) : undefined;
  if (burnInBackend === "drawtext") {
    console.log("Burn-in: drawtext (stock ffmpeg; no libass required).");
  } else if (burnInBackend === "subtitles") {
    console.log("Burn-in: subtitles/ass (libass).");
  }
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
      burnInBackend,
    });
    segments.push(output);
  }
  let segmentFiles: string[] = [];
  let manifestPath: string | null = null;
  if (opts.segmentsDir) {
    const written = await writeNamedSegments({
      segments,
      clips: opts.clips,
      dir: opts.segmentsDir,
      word: opts.word ?? "",
      pad: opts.pad ?? SUPERCUT_DEFAULT_PAD,
      width: opts.width,
      height: opts.height,
      fps: opts.fps,
      burnIn: opts.burnIn,
    });
    segmentFiles = written.files;
    manifestPath = written.manifestPath;
  }
  if (opts.outPath) {
    await concatSegments(opts.ffmpeg, segments, opts.outPath);
  }
  return { outPath: opts.outPath ?? null, segmentFiles, manifestPath };
}
