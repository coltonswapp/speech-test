// Seeds the clip queue (lib/experiments/clips/queue.ts) with the Shorts from
// the competitor video index.
//
//   pnpm clip:queue-seed <kiku-videos-dump.json> <videos-by-channel.cache.jsonl>          # dry run: stats only
//   pnpm clip:queue-seed <kiku-videos-dump.json> <videos-by-channel.cache.jsonl> --write  # merge into R2
//
// The dump says which videos are Shorts; the cache (written by
// fetch_video_info.py) has each video's channel, channel id and duration.
// Videos missing from the cache (private or deleted) are left out.
//
// Safe to re-run: entries already in the queue keep their status and note;
// only the title, channel and duration are refreshed.
import { readFile } from "node:fs/promises";
import { GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import {
  clipQueueFlags,
  clipQueueSchema,
  type ClipQueue,
  type ClipQueueChannel,
  type ClipQueueItem,
} from "../lib/experiments/clips/queue";
import { YOUTUBE_ID_PATTERN } from "../lib/experiments/clips/types";

const QUEUE_KEY = "experiments/clip-queue/queue.json";

type DumpEntry = { youtube_id: string; title: string; is_short: boolean };
type CacheEntry = {
  id: string;
  title: string;
  duration: number | null;
  channel: string | null;
  uploader: string | null;
  channel_id: string | null;
};

function env(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name} in .env.local`);
  return value;
}

function r2() {
  const s3 = new S3Client({
    region: "auto",
    endpoint: process.env.R2_ENDPOINT?.trim() || `https://${env("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com`,
    credentials: { accessKeyId: env("R2_ACCESS_KEY_ID"), secretAccessKey: env("R2_SECRET_ACCESS_KEY") },
  });
  return { s3, bucket: env("R2_BUCKET_NAME") };
}

async function readQueue(): Promise<ClipQueue | null> {
  const { s3, bucket } = r2();
  try {
    const out = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: QUEUE_KEY }));
    const text = await out.Body!.transformToString("utf8");
    return clipQueueSchema.parse(JSON.parse(text));
  } catch (error) {
    if ((error as { name?: string }).name === "NoSuchKey") return null;
    throw error;
  }
}

async function writeQueue(queue: ClipQueue): Promise<void> {
  const { s3, bucket } = r2();
  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: QUEUE_KEY,
      Body: JSON.stringify(queue),
      ContentType: "application/json",
    })
  );
}

async function main() {
  const args = process.argv.slice(2);
  const write = args.includes("--write");
  const [dumpPath, cachePath] = args.filter((a) => !a.startsWith("--"));
  if (!dumpPath || !cachePath) {
    console.error("Usage: pnpm clip:queue-seed <kiku-videos-dump.json> <videos-by-channel.cache.jsonl> [--write]");
    process.exit(1);
  }

  const dump = JSON.parse(await readFile(dumpPath, "utf8")) as DumpEntry[];
  const cache = new Map<string, CacheEntry>();
  for (const line of (await readFile(cachePath, "utf8")).split("\n")) {
    if (!line.trim().startsWith("{")) continue;
    const entry = JSON.parse(line) as CacheEntry;
    cache.set(entry.id, entry);
  }

  const now = new Date().toISOString();
  const channels = new Map<string, ClipQueueChannel>();
  const shorts: Omit<ClipQueueItem, "status" | "addedAt" | "updatedAt">[] = [];
  let missing = 0;
  const seen = new Set<string>();

  for (const entry of dump) {
    if (!YOUTUBE_ID_PATTERN.test(entry.youtube_id) || seen.has(entry.youtube_id)) continue;
    seen.add(entry.youtube_id);
    const info = cache.get(entry.youtube_id);
    // yt-dlp got nothing for these (private or deleted): only a stand-in title.
    if (!info || (!info.channel_id && !info.channel && !info.uploader)) {
      missing++;
      continue;
    }
    const channelName = (info.channel ?? info.uploader ?? "").trim() || "Unknown channel";
    const channelId = info.channel_id ?? null;
    if (channelId) {
      const c = channels.get(channelId) ?? { channelId, name: channelName, dumpShorts: 0, dumpRegular: 0 };
      if (entry.is_short) c.dumpShorts++;
      else c.dumpRegular++;
      channels.set(channelId, c);
    }
    if (!entry.is_short) continue;
    shorts.push({
      videoId: entry.youtube_id,
      title: info.title || entry.title,
      channelName,
      channelId,
      durationSec: typeof info.duration === "number" ? info.duration : null,
      source: "dump",
    });
  }

  const existing = await readQueue();
  const byId = new Map((existing?.items ?? []).map((item) => [item.videoId, item]));
  let added = 0;
  for (const s of shorts) {
    const prev = byId.get(s.videoId);
    if (prev) {
      byId.set(s.videoId, { ...prev, title: s.title, channelName: s.channelName, channelId: s.channelId, durationSec: s.durationSec });
    } else {
      byId.set(s.videoId, { ...s, status: "queued", addedAt: now, updatedAt: now });
      added++;
    }
  }
  const prevChannels = new Map((existing?.channels ?? []).map((c) => [c.channelId, c]));
  const mergedChannels = [...channels.values()].map((c) => ({
    ...c,
    ...(prevChannels.get(c.channelId)?.scannedAt ? { scannedAt: prevChannels.get(c.channelId)!.scannedAt } : {}),
  }));
  for (const [id, c] of prevChannels) if (!channels.has(id)) mergedChannels.push(c);

  const items = [...byId.values()];
  const queue: ClipQueue = { items, channels: mergedChannels, updatedAt: now };
  clipQueueSchema.parse(queue);

  // Stats
  const flagCounts = new Map<string, number>();
  let clean = 0;
  for (const item of items) {
    const flags = clipQueueFlags(item);
    if (flags.length === 0) clean++;
    for (const f of flags) flagCounts.set(f, (flagCounts.get(f) ?? 0) + 1);
  }
  const shortChannels = new Set(items.map((i) => i.channelId ?? i.channelName));
  console.log(`Dump: ${dump.length} videos; ${missing} not in the cache (private/deleted), left out.`);
  console.log(`Shorts: ${shorts.length} from ${shortChannels.size} channels.`);
  console.log(`Queue: ${existing?.items.length ?? 0} before, ${added} new, ${items.length} after.`);
  console.log(`No warnings: ${clean}. Warnings (an entry can have several):`);
  for (const [flag, n] of [...flagCounts].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(5)}  ${flag}`);
  const top = mergedChannels
    .filter((c) => c.dumpShorts > 0)
    .sort((a, b) => b.dumpShorts + b.dumpRegular - (a.dumpShorts + a.dumpRegular))
    .slice(0, 10);
  console.log("Top channels by videos in the dump:");
  for (const c of top) console.log(`  ${String(c.dumpShorts).padStart(3)} shorts ${String(c.dumpRegular).padStart(3)} regular  ${c.name}`);

  if (!write) {
    console.log("\nDry run. Add --write to save the queue to R2.");
    return;
  }
  await writeQueue(queue);
  console.log(`\nSaved ${QUEUE_KEY} (${(JSON.stringify(queue).length / 1024).toFixed(0)} KB).`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
