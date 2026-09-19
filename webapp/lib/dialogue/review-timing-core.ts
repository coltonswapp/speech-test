import { z } from "zod";
import type { VariantTokenSync } from "@/lib/dialogue/types";

/** Pure half of the review-timing telemetry (KA-8): schema and math. */

export const reviewTimingSchema = z.object({
  autoStampedAt: z.string().optional(),
  /** Flat startSeconds per token at auto-stamp time, null for untimed. */
  autoStamps: z.array(z.number().nullable()).optional(),
  autoFlagCount: z.number().int().optional(),
  openedAt: z.string().optional(),
  reviewedAt: z.string().optional(),
  publishedAt: z.string().optional(),
  /** tokenSync.source at publish; "human" when absent (legacy takes). */
  publishedSource: z.enum(["human", "auto", "reviewed"]).optional(),
  tokenCount: z.number().int().optional(),
  lineCount: z.number().int().optional(),
  /** Lines with at least one token moved vs. the auto stamps (auto takes only). */
  linesTouched: z.number().int().optional(),
  tokensMoved: z.number().int().optional(),
  maxCorrectionMs: z.number().optional(),
});
export type ReviewTiming = z.infer<typeof reviewTimingSchema>;

export function flatStamps(sync: VariantTokenSync): Array<number | null> {
  return sync.lines.flatMap((line) => line.tokens.map((t) => t.startSeconds));
}

/** Correction stats of the current stamps against the auto-stamp snapshot. */
export function correctionStats(
  sync: VariantTokenSync,
  autoStamps: Array<number | null> | undefined
): { linesTouched: number; tokensMoved: number; maxCorrectionMs: number } | null {
  if (!autoStamps) return null;
  const current = flatStamps(sync);
  if (current.length !== autoStamps.length) return null;
  let tokensMoved = 0;
  let maxCorrectionMs = 0;
  const touchedLines = new Set<number>();
  let k = 0;
  sync.lines.forEach((line, li) => {
    for (let ti = 0; ti < line.tokens.length; ti++, k++) {
      const before = autoStamps[k];
      const after = current[k];
      if (before == null || after == null) continue;
      const delta = Math.abs(after - before) * 1000;
      if (delta > 1) {
        tokensMoved++;
        touchedLines.add(li);
        if (delta > maxCorrectionMs) maxCorrectionMs = delta;
      }
    }
  });
  return { linesTouched: touchedLines.size, tokensMoved, maxCorrectionMs: Math.round(maxCorrectionMs) };
}

function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const s = [...values].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

function minutesBetween(from: string | undefined, to: string | undefined): number | null {
  if (!from || !to) return null;
  const ms = new Date(to).getTime() - new Date(from).getTime();
  return Number.isFinite(ms) && ms >= 0 ? ms / 60000 : null;
}

export type ReviewTimingSummary = {
  /** Auto and reviewed takes vs. hand-stamped takes. */
  bySource: Array<{
    source: "auto" | "human";
    published: number;
    medianOpenToPublishMinutes: number | null;
    withOpenTiming: number;
    /** Auto only: share of lines the reviewer did not touch. */
    linesUntouchedPct: number | null;
    /** Auto only: share of published auto takes with a correction over 200 ms. */
    correctionsOver200msPct: number | null;
  }>;
  since: string | null;
};

export function summarizeReviewTiming(rows: Iterable<ReviewTiming>): ReviewTimingSummary {
  const published = [...rows].filter((r) => r.publishedAt);
  const groups: Record<"auto" | "human", ReviewTiming[]> = { auto: [], human: [] };
  for (const r of published) {
    groups[r.publishedSource === "human" || !r.publishedSource ? "human" : "auto"].push(r);
  }
  const bySource = (["auto", "human"] as const).map((source) => {
    const rs = groups[source];
    const open = rs.map((r) => minutesBetween(r.openedAt, r.publishedAt)).filter((m): m is number => m != null);
    const withLines = rs.filter((r) => r.linesTouched != null && r.lineCount);
    const linesTotal = withLines.reduce((n, r) => n + (r.lineCount ?? 0), 0);
    const linesTouched = withLines.reduce((n, r) => n + (r.linesTouched ?? 0), 0);
    const withCorr = rs.filter((r) => r.maxCorrectionMs != null);
    return {
      source,
      published: rs.length,
      medianOpenToPublishMinutes: median(open),
      withOpenTiming: open.length,
      linesUntouchedPct:
        source === "auto" && linesTotal > 0 ? (100 * (linesTotal - linesTouched)) / linesTotal : null,
      correctionsOver200msPct:
        source === "auto" && withCorr.length > 0
          ? (100 * withCorr.filter((r) => (r.maxCorrectionMs ?? 0) > 200).length) / withCorr.length
          : null,
    };
  });
  const dates = published.map((r) => r.publishedAt!).sort();
  return { bySource, since: dates[0] ?? null };
}
