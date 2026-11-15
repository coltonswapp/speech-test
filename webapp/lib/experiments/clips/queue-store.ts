import "server-only";
import { getObject, objectExists, putObject } from "@/lib/storage/r2";
import { clipQueueSchema, type ClipQueue } from "@/lib/experiments/clips/queue";

// One file for the whole queue (a few thousand entries, ~1-2 MB). Writes are
// read-modify-write: fine for one editor, but two writes at the same moment
// can lose one of them.
export const CLIP_QUEUE_KEY = "experiments/clip-queue/queue.json";

export async function readClipQueue(): Promise<ClipQueue> {
  if (!(await objectExists(CLIP_QUEUE_KEY))) {
    return { items: [], channels: [], updatedAt: new Date(0).toISOString() };
  }
  const parsed = clipQueueSchema.safeParse(
    JSON.parse((await getObject(CLIP_QUEUE_KEY)).toString("utf8"))
  );
  if (!parsed.success) throw new Error(`Clip queue is malformed: ${parsed.error.message}`);
  return parsed.data;
}

export async function writeClipQueue(queue: ClipQueue): Promise<ClipQueue> {
  const next = { ...queue, updatedAt: new Date().toISOString() };
  await putObject(CLIP_QUEUE_KEY, Buffer.from(JSON.stringify(next)), "application/json");
  return next;
}
