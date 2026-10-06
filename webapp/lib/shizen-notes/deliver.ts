import "server-only";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { shizenNoteJob } from "@/lib/db/schema";
import { shoheiDeliveryPayload } from "./payload";
import { resolveShoheiDeliveryTarget } from "./delivery-target";

const DELIVERY_TIMEOUT_MS = 15_000;

/** Posts a stored job to Shohei. Shohei's routine decides where it goes next. */
export async function deliverToShohei(jobId: string): Promise<void> {
  const [job] = await db.select().from(shizenNoteJob).where(eq(shizenNoteJob.id, jobId));
  if (!job) return;

  const target = resolveShoheiDeliveryTarget();
  if (!target.ok) {
    await markJob(jobId, "queued", target.error);
    return;
  }

  const payload = shoheiDeliveryPayload(job);

  try {
    const response = await fetch(target.url, {
      method: "POST",
      headers: target.headers,
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
