// Stitch clip-library hits for a spoken word into one mp4.
//
// Footage: R2 only stores `experiments/clips/<id>/draft.json` and `clip.wav`
// (mono 16 kHz audio for ASR/align). There is no stored video. The public
// payload's media.source is "youtube" + video_id; Studio plays the YouTube
// iframe. This script downloads just the padded hit range with
// `yt-dlp --download-sections` and caches it under `.cache/clip-supercut/`.
//
//   pnpm clip:supercut --word ちゃう --limit 10 --pad 0.8 --out /tmp/chau.mp4
//   pnpm clip:supercut --word ています --feed --burn-in --dry-run
//
// Needs DATABASE_URL (clip_token_index; apply 0026 then `pnpm clip:index-backfill
// --write`) plus yt-dlp and ffmpeg on PATH. `--studio http://localhost:3000`
// searches through Studio's token-search route instead of the DB.
//
// Do not point this at production until the migration and backfill have been
// approved and applied.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, stat } from "node:fs/promises";
import path from "node:path";
import {
  cacheFileName,
  defaultOutPath,
  findFontPath,
  paddedRange,
  parseSupercutArgs,
  runCommand,
  sectionTime,
  stitchLocalClips,
  youtubeUrl,
  type SupercutArgs,
  type SupercutHit,
} from "../lib/experiments/clips/supercut";

function requireTool(name: string) {
  const probe = spawnSync(name, ["-version"], { stdio: "ignore" });
  if (probe.error) {
    throw new Error(`${name} isn’t installed. Install it and put it on PATH (e.g. brew install ${name}).`);
  }
}

async function searchViaStudio(args: SupercutArgs): Promise<SupercutHit[]> {
  const base = (args.studio ?? "http://localhost:3000").replace(/\/$/, "");
  const params = new URLSearchParams();
  params.set("word", args.word);
  if (args.level !== null) params.set("level", String(args.level));
  if (args.feed) params.set("feed", "1");
  if (!args.listed) params.set("listed", "0");
  params.set("limit", String(args.limit));
  const headers: Record<string, string> = {};
  const agentToken = process.env.STUDIO_AGENT_TOKEN?.trim();
  if (agentToken) headers.Authorization = `Bearer ${agentToken}`;
  const res = await fetch(`${base}/api/experiments/clips/token-search?${params}`, { headers });
  const body = (await res.json().catch(() => null)) as { hits?: SupercutHit[]; error?: string } | null;
  if (!res.ok) {
    throw new Error(body?.error ?? `Studio search failed (HTTP ${res.status}).`);
  }
  return body?.hits ?? [];
}

async function searchViaDb(args: SupercutArgs): Promise<SupercutHit[]> {
  const { db } = await import("../lib/db/standalone-client");
  const { isUndefinedTable, searchClipTokenIndex } = await import(
    "../lib/experiments/clips/token-index-db"
  );
  try {
    const result = await searchClipTokenIndex(db, {
      word: args.word,
      level: args.level,
      feed: args.feed,
      listed: args.listed,
      limit: args.limit,
    });
    return result.hits;
  } catch (error) {
    if (isUndefinedTable(error, "clip_token_index")) {
      throw new Error(
        "clip_token_index does not exist yet. Apply drizzle 0026_clip_token_index, then pnpm clip:index-backfill --write."
      );
    }
    throw error;
  }
}

async function downloadSection(
  videoId: string,
  startSec: number,
  endSec: number,
  outPath: string
): Promise<void> {
  try {
    const info = await stat(outPath);
    if (info.size > 0) return;
  } catch {
    // not cached
  }
  await mkdir(path.dirname(outPath), { recursive: true });
  const tmpPattern = outPath.replace(/\.mp4$/i, ".%(ext)s");
  await runCommand(
    "yt-dlp",
    [
      "-f",
      "bv*[height<=1080]+ba/b",
      "--no-playlist",
      "--download-sections",
      `*${sectionTime(startSec)}-${sectionTime(endSec)}`,
      "--force-keyframes-at-cuts",
      "--merge-output-format",
      "mp4",
      "-o",
      tmpPattern,
      youtubeUrl(videoId),
    ],
    { inherit: true }
  );
  if (!existsSync(outPath)) {
    throw new Error(`yt-dlp finished but ${outPath} is missing.`);
  }
}

async function main() {
  const args = parseSupercutArgs(process.argv.slice(2));
  const hits = args.studio ? await searchViaStudio(args) : await searchViaDb(args);
  console.log(`${hits.length} hit${hits.length === 1 ? "" : "s"} for “${args.word}”.`);
  for (const hit of hits) {
    console.log(
      `  ${hit.clipId}  ${hit.videoId}  line ${hit.lineIndex}  ${hit.startSec.toFixed(2)}–${hit.endSec.toFixed(2)}s  ${hit.lineText}`
    );
  }
  if (args.dryRun) {
    console.log("Dry run. Drop --dry-run to download sections and stitch.");
    return;
  }
  if (hits.length === 0) {
    throw new Error("No hits. Nothing to stitch.");
  }
  requireTool("yt-dlp");
  requireTool("ffmpeg");
  const cacheDir = path.resolve(args.cache);
  const workDir = path.join(cacheDir, "work");
  await mkdir(cacheDir, { recursive: true });
  const local = [];
  for (const hit of hits) {
    const range = paddedRange(hit.startSec, hit.endSec, args.pad);
    const cached = path.join(cacheDir, cacheFileName(hit.videoId, range.startSec, range.endSec));
    console.log(`Downloading ${hit.videoId} ${range.startSec}–${range.endSec}s…`);
    try {
      await downloadSection(hit.videoId, range.startSec, range.endSec, cached);
    } catch (error) {
      console.warn(`  skipped ${hit.clipId}: ${error instanceof Error ? error.message : error}`);
      continue;
    }
    local.push({
      path: cached,
      lineText: hit.lineText,
      matchedText: hit.matchedText,
      charStart: hit.charStart,
    });
  }
  if (local.length === 0) {
    throw new Error("Every download failed. See warnings above.");
  }
  const outPath = path.resolve(args.out ?? defaultOutPath(args.word));
  await mkdir(path.dirname(outPath), { recursive: true });
  await stitchLocalClips({
    ffmpeg: "ffmpeg",
    clips: local,
    outPath,
    width: args.width,
    height: args.height,
    fps: args.fps,
    burnIn: args.burnIn,
    fontPath: findFontPath(),
    workDir,
  });
  console.log(`Wrote ${outPath} (${local.length} clip${local.length === 1 ? "" : "s"}).`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
