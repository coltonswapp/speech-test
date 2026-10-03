import "server-only";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { shizenNoteJob } from "@/lib/db/schema";

const DELIVERY_TIMEOUT_MS = 15_000;

/** Posts a stored job to Shohei. Shohei's routine decides where it goes next. */
export async function deliverToShohei(jobId: string): Promise<void> {
  const [job] = await db.select().from(shizenNoteJob).where(eq(shizenNoteJob.id, jobId));
  if (!job) return;

  const url = process.env.SHOHEI_DELIVERY_URL?.trim();
  if (!url) {
    await markJob(jobId, "queued", "SHOHEI_DELIVERY_URL is not set");
    return;
  }

  const payload = {
    job_id: job.id,
    source: job.source,
    source_id: job.sourceId,
    ...(job.title ? { title: job.title } : {}),
    note: job.note,
    agent: job.agent,
    metadata: {
      url: job.url,
      created_at: job.noteCreatedAt.toISOString(),
    },
  };

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(DELIVERY_TIMEOUT_MS),
    });
    if (!response.ok) {
      const detail = (await response.text().catch(() => "")).slice(0, 500);
      await markJob(jobId, "failed", `HTTP ${response.status}${detail ? `: ${detail}` : ""}`);
      return;
    }
    await markJob(jobId, "delivered", null);
  } catch (error) {
    await markJob(jobId, "failed", error instanceof Error ? error.message : String(error));
  }
}

async function markJob(jobId: string, status: string, error: string | null) {
  await db
    .update(shizenNoteJob)
    .set({ status, error, updatedAt: new Date() })
    .where(eq(shizenNoteJob.id, jobId));
}
