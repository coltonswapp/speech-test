import "server-only";
import { randomBytes } from "node:crypto";
import { after } from "next/server";
import { db } from "@/lib/db/client";
import { shizenNoteJob } from "@/lib/db/schema";
import { deliverToShohei } from "./deliver";
import type { ShizenNote } from "./schema";

/** Stores the note as a job and delivers it after the response is sent. */
export async function acceptNote(note: ShizenNote): Promise<string> {
  const jobId = `job_${randomBytes(9).toString("base64url")}`;
  await db.insert(shizenNoteJob).values({
    id: jobId,
    source: note.source,
    sourceId: note.source_id,
    title: note.title ?? null,
    note: note.note,
    agent: note.agent,
    url: note.metadata.url,
    noteCreatedAt: new Date(note.metadata.created_at),
  });
  after(() => deliverToShohei(jobId));
  return jobId;
}
