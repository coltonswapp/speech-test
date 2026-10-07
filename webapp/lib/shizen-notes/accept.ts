import "server-only";
import { randomBytes } from "node:crypto";
import { after } from "next/server";
import { db } from "@/lib/db/client";
import { shizenNoteJob } from "@/lib/db/schema";
import { putObject } from "@/lib/storage/r2";
import { deliverToShohei } from "./deliver";
import { screenshotObjectKey } from "./payload";
import type { ShizenNote } from "./schema";

/** Stores the note as a job and delivers it after the response is sent. */
export async function acceptNote(note: ShizenNote): Promise<string> {
  const jobId = `job_${randomBytes(9).toString("base64url")}`;
  const screenshotKey = note.metadata.screenshot_jpeg
    ? await uploadScreenshot(jobId, note.metadata.screenshot_jpeg)
    : null;
  await db.insert(shizenNoteJob).values({
    id: jobId,
    source: note.source,
    sourceId: note.source_id,
    title: note.title ?? null,
    note: note.note,
    agent: note.agent,
    url: note.metadata.url,
    noteCreatedAt: new Date(note.metadata.created_at),
    screenshotObjectKey: screenshotKey,
  });
  after(() => deliverToShohei(jobId));
  return jobId;
}

/** A failed upload drops the screenshot, not the note. */
async function uploadScreenshot(jobId: string, base64: string): Promise<string | null> {
  const key = screenshotObjectKey(jobId, randomBytes(12).toString("base64url"));
  try {
    await putObject(key, Buffer.from(base64, "base64"), "image/jpeg");
    return key;
  } catch (error) {
    console.error(`[shizen-notes] Screenshot upload failed for ${jobId}:`, error);
    return null;
  }
}
