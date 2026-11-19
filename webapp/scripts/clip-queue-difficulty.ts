// Gives clip-queue entries a soft difficulty (CEFR, A1–C2) from the local
// video dump, so batches can target a level:
//
//   pnpm clip:queue-difficulty <videos-by-channel.json>          # dry run: stats only
//   pnpm clip:queue-difficulty <videos-by-channel.json> --write  # save to R2
//
// The dump is { "<channel name>": { shorts: [...], regular: [...] } } with a
// `difficulty` on each video. An entry gets its own video's level when the
// dump has it ("video"); otherwise the level most of its channel's videos
// have ("channel", matched by channel name). Entries matching neither are
// left as they are. Only difficulty changes; status, notes and the rest stay.
//
// Safe to re-run, e.g. after adding Shorts with find_channel_shorts.
import { readFile } from "node:fs/promises";
import { GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import {
  CLIP_QUEUE_DIFFICULTIES,
  clipQueueDifficultySchema,
  clipQueueSchema,
  type ClipQueue,
  type ClipQueueDifficulty,
} from "../lib/experiments/clips/queue";

const QUEUE_KEY = "experiments/clip-queue/queue.json";

type DumpVideo = { videoId: string; difficulty?: string | null };
type Dump = Record<string, { shorts?: DumpVideo[]; regular?: DumpVideo[] }>;

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

async function readQueue(): Promise<ClipQueue> {
  const { s3, bucket } = r2();
  const out = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: QUEUE_KEY }));
  return clipQueueSchema.parse(JSON.parse(await out.Body!.transformToString("utf8")));
}

async function writeQueue(queue: ClipQueue): Promise<void> {
  const { s3, bucket } = r2();
  await s3.send(
    new PutObjectCommand({ Bucket: bucket, Key: QUEUE_KEY, Body: JSON.stringify(queue), ContentType: "application/json" })
  );
}

const channelKey = (name: string) => name.trim().toLowerCase();

function level(value: unknown): ClipQueueDifficulty | null {
  const parsed = clipQueueDifficultySchema.safeParse(typeof value === "string" ? value.trim().toUpperCase() : value);
  return parsed.success ? parsed.data : null;
}

async function main() {
  const args = process.argv.slice(2);
  const write = args.includes("--write");
  const [dumpPath] = args.filter((a) => !a.startsWith("--"));
  if (!dumpPath) {
    console.error("Usage: pnpm clip:queue-difficulty <videos-by-channel.json> [--write]");
    process.exit(1);
  }

  const dump = JSON.parse(await readFile(dumpPath, "utf8")) as Dump;
  const byVideo = new Map<string, ClipQueueDifficulty>();
  const byChannel = new Map<string, ClipQueueDifficulty>();
  for (const [name, lists] of Object.entries(dump)) {
    const counts = new Map<ClipQueueDifficulty, number>();
    for (const video of [...(lists.shorts ?? []), ...(lists.regular ?? [])]) {
      const l = level(video.difficulty);
      if (!l) continue;
      byVideo.set(video.videoId, l);
      counts.set(l, (counts.get(l) ?? 0) + 1);
    }
    // Most common level; a tie goes to the easier one.
    let best: ClipQueueDifficulty | null = null;
    for (const l of CLIP_QUEUE_DIFFICULTIES) if (best === null || (counts.get(l) ?? 0) > (counts.get(best) ?? 0)) best = l;
    if (best && (counts.get(best) ?? 0) > 0) byChannel.set(channelKey(name), best);
  }

  const queue = await readQueue();
  let changed = 0;
  const tally = new Map<string, number>();
  const items = queue.items.map((item) => {
    const fromVideo = byVideo.get(item.videoId);
    const fromChannel = byChannel.get(channelKey(item.channelName));
    const next =
      fromVideo ? { difficulty: fromVideo, difficultyFrom: "video" as const }
      : fromChannel ? { difficulty: fromChannel, difficultyFrom: "channel" as const }
      : null;
    const result = next ?? (item.difficulty ? { difficulty: item.difficulty, difficultyFrom: item.difficultyFrom } : null);
    const toDo = item.status === "queued";
    const key = result ? `${result.difficulty} (${result.difficultyFrom ?? "?"})` : "unrated";
    if (toDo) tally.set(key, (tally.get(key) ?? 0) + 1);
    if (!next || (item.difficulty === next.difficulty && item.difficultyFrom === next.difficultyFrom)) return item;
    changed++;
    return { ...item, ...next };
  });

  console.log(`Dump: ${byVideo.size} rated videos, ${byChannel.size} channels with a usual level.`);
  console.log(`Queue: ${queue.items.length} entries; ${changed} get a new or changed difficulty.`);
  console.log("Queued entries (not skipped) by difficulty:");
  for (const [key, n] of [...tally].sort((a, b) => a[0].localeCompare(b[0]))) console.log(`  ${String(n).padStart(5)}  ${key}`);

  if (!write) {
    console.log("\nDry run. Add --write to save the queue to R2.");
    return;
  }
  if (changed === 0) return console.log("\nNothing to save.");
  // Read again right before writing so an entry added meanwhile isn't lost.
  const latest = await readQueue();
  const updates = new Map(items.map((i) => [i.videoId, i]));
  const merged = latest.items.map((i) => {
    const u = updates.get(i.videoId);
    return u?.difficulty ? { ...i, difficulty: u.difficulty, difficultyFrom: u.difficultyFrom } : i;
  });
  const next: ClipQueue = { ...latest, items: merged, updatedAt: new Date().toISOString() };
  clipQueueSchema.parse(next);
  await writeQueue(next);
  console.log(`\nSaved ${QUEUE_KEY}.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
