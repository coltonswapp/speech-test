import "server-only";
import { eq, like } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { appSettings, type ttsVariant } from "@/lib/db/schema";
import { parseVariantTokenSync } from "@/lib/dialogue/token-sync";
import {
  correctionStats,
  flatStamps,
  reviewTimingSchema,
  type ReviewTiming,
} from "@/lib/dialogue/review-timing-core";
import type { VariantTokenSync } from "@/lib/dialogue/types";

export { summarizeReviewTiming, type ReviewTiming, type ReviewTimingSummary } from "@/lib/dialogue/review-timing-core";

/**
 * Review timing telemetry (KA-8): one app_settings row per take that records
 * when it was auto-stamped, first opened in the token editor, marked
 * reviewed and published, plus how far the reviewer moved the auto stamps.
 * Turns the "minutes saved per scene" estimate into a measurement without a
 * migration.
 */

const KEY_PREFIX = "review-timing:";

function key(variantId: string): string {
  return `${KEY_PREFIX}${variantId}`;
}

export async function getReviewTiming(variantId: string): Promise<ReviewTiming | null> {
  const row = await db.query.appSettings.findFirst({ where: eq(appSettings.key, key(variantId)) });
  if (!row) return null;
  const parsed = reviewTimingSchema.safeParse(row.value);
  return parsed.success ? parsed.data : null;
}

async function mergeReviewTiming(variantId: string, patch: Partial<ReviewTiming>): Promise<ReviewTiming> {
  const current = (await getReviewTiming(variantId)) ?? {};
  const next: ReviewTiming = { ...current, ...patch };
  await db
    .insert(appSettings)
    .values({ key: key(variantId), value: next })
    .onConflictDoUpdate({ target: appSettings.key, set: { value: next } });
  return next;
}

export async function recordAutoStamp(variantId: string, sync: VariantTokenSync): Promise<void> {
  await mergeReviewTiming(variantId, {
    autoStampedAt: new Date().toISOString(),
    autoStamps: flatStamps(sync),
    autoFlagCount: sync.flags?.length ?? 0,
    tokenCount: flatStamps(sync).length,
    lineCount: sync.lines.length,
    // A re-run resets the review clock.
    openedAt: undefined,
    reviewedAt: undefined,
  });
}

export type ReviewEvent = "opened" | "reviewed";

/** `opened` is recorded once (first open); `reviewed` overwrites. */
export async function recordReviewEvent(variantId: string, event: ReviewEvent): Promise<void> {
  const current = await getReviewTiming(variantId);
  const now = new Date().toISOString();
  if (event === "opened") {
    if (current?.openedAt) return;
    await mergeReviewTiming(variantId, { openedAt: now });
    return;
  }
  await mergeReviewTiming(variantId, { reviewedAt: now });
}

export async function recordPublish(variant: typeof ttsVariant.$inferSelect): Promise<void> {
  const sync = parseVariantTokenSync(variant.tokenSync);
  const current = await getReviewTiming(variant.id);
  const stats = sync ? correctionStats(sync, current?.autoStamps) : null;
  await mergeReviewTiming(variant.id, {
    publishedAt: new Date().toISOString(),
    publishedSource: sync?.source ?? "human",
    tokenCount: sync ? flatStamps(sync).length : current?.tokenCount,
    lineCount: sync?.lines.length ?? current?.lineCount,
    ...(stats ?? {}),
  });
}

export async function clearReviewTiming(variantId: string): Promise<void> {
  await db.delete(appSettings).where(eq(appSettings.key, key(variantId)));
}

export async function listReviewTiming(): Promise<Map<string, ReviewTiming>> {
  const rows = await db.select().from(appSettings).where(like(appSettings.key, `${KEY_PREFIX}%`));
  const out = new Map<string, ReviewTiming>();
  for (const row of rows) {
    const parsed = reviewTimingSchema.safeParse(row.value);
    if (parsed.success) out.set(row.key.slice(KEY_PREFIX.length), parsed.data);
  }
  return out;
}

