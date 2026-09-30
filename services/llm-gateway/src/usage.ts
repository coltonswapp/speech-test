import { FieldValue, getFirestore } from "firebase-admin/firestore";

import { billedOutputTokens, estimateCostUSD, microsToUSD, usdToMicros } from "./pricing.js";
import { log } from "./log.js";
import type { GeminiUsage } from "./gemini.js";

export const USAGE_PERIODS = ["day", "week", "month"] as const;
export type UsagePeriod = (typeof USAGE_PERIODS)[number];

export type UsageFeatureTotals = {
  calls: number;
  promptTokens: number;
  outputTokens: number;
  estimatedCostUSD: number;
};

export type UsageReport = {
  period: UsagePeriod;
  periodKey: string;
  calls: number;
  promptTokens: number;
  outputTokens: number;
  estimatedCostUSD: number;
  hasUnpriced: boolean;
  byFeature: Record<string, UsageFeatureTotals>;
};

export function isUsagePeriod(value: unknown): value is UsagePeriod {
  return typeof value === "string" && (USAGE_PERIODS as readonly string[]).includes(value);
}

export function periodKeys(at = new Date()): Record<UsagePeriod, string> {
  const year = at.getUTCFullYear();
  const month = String(at.getUTCMonth() + 1).padStart(2, "0");
  const day = String(at.getUTCDate()).padStart(2, "0");
  return {
    day: `${year}-${month}-${day}`,
    week: isoWeekKey(at),
    month: `${year}-${month}`,
  };
}

/** ISO-8601 week in UTC, e.g. `2026-W40`. */
function isoWeekKey(at: Date): string {
  const date = new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate()));
  const weekday = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - weekday);
  const weekYear = date.getUTCFullYear();
  const yearStart = new Date(Date.UTC(weekYear, 0, 1));
  const week = Math.ceil(((date.getTime() - yearStart.getTime()) / 86_400_000 + 1) / 7);
  return `${weekYear}-W${String(week).padStart(2, "0")}`;
}

function periodDoc(scope: string, period: UsagePeriod, key: string) {
  return getFirestore().collection("llmUsage").doc(scope).collection("periods").doc(`${period}_${key}`);
}

/**
 * Increments day, week, and month docs for this uid and for `_product`.
 * Does not store prompt text. Failures are logged and do not fail the generate response.
 */
export function recordUsage(uid: string, feature: string, model: string, usage: GeminiUsage): void {
  const promptTokens = usage.promptTokenCount;
  const outputTokens = billedOutputTokens(
    usage.promptTokenCount,
    usage.candidatesTokenCount,
    usage.totalTokenCount,
  );
  const cost = estimateCostUSD(model, promptTokens, outputTokens);
  const costMicros = cost ? usdToMicros(cost.totalUSD) : 0;
  const keys = periodKeys();
  const scopes = [uid, "_product"];
  const writes = scopes.flatMap((scope) =>
    (USAGE_PERIODS as readonly UsagePeriod[]).map((period) => {
      const payload: Record<string, unknown> = {
        calls: FieldValue.increment(1),
        promptTokens: FieldValue.increment(promptTokens),
        outputTokens: FieldValue.increment(outputTokens),
        estimatedCostMicros: FieldValue.increment(costMicros),
        [`byFeature.${feature}.calls`]: FieldValue.increment(1),
        [`byFeature.${feature}.promptTokens`]: FieldValue.increment(promptTokens),
        [`byFeature.${feature}.outputTokens`]: FieldValue.increment(outputTokens),
        [`byFeature.${feature}.estimatedCostMicros`]: FieldValue.increment(costMicros),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (!cost) {
        payload.unpricedCalls = FieldValue.increment(1);
        payload[`byFeature.${feature}.unpricedCalls`] = FieldValue.increment(1);
      }
      return periodDoc(scope, period, keys[period]).set(payload, { merge: true });
    }),
  );

  void Promise.all(writes).catch((err: unknown) => {
    log("ERROR", "usage write failed", {
      error: err instanceof Error ? err.message : String(err),
      feature,
    });
  });
}

export async function readUsage(scope: string, period: UsagePeriod): Promise<UsageReport> {
  const key = periodKeys()[period];
  const snap = await periodDoc(scope, period, key).get();
  return reportFromDoc(period, key, snap.data() as Record<string, unknown> | undefined);
}

function reportFromDoc(period: UsagePeriod, periodKey: string, data: Record<string, unknown> | undefined): UsageReport {
  const byFeature: Record<string, UsageFeatureTotals> = {};
  const rawFeatures = data?.byFeature;
  if (rawFeatures && typeof rawFeatures === "object") {
    for (const [name, value] of Object.entries(rawFeatures as Record<string, Record<string, unknown>>)) {
      if (!value || typeof value !== "object") continue;
      byFeature[name] = {
        calls: numberField(value.calls),
        promptTokens: numberField(value.promptTokens),
        outputTokens: numberField(value.outputTokens),
        estimatedCostUSD: microsToUSD(numberField(value.estimatedCostMicros)),
      };
    }
  }
  return {
    period,
    periodKey,
    calls: numberField(data?.calls),
    promptTokens: numberField(data?.promptTokens),
    outputTokens: numberField(data?.outputTokens),
    estimatedCostUSD: microsToUSD(numberField(data?.estimatedCostMicros)),
    hasUnpriced: numberField(data?.unpricedCalls) > 0,
    byFeature,
  };
}

function numberField(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

export function featuresRanked(report: UsageReport): Array<UsageFeatureTotals & { feature: string }> {
  return Object.entries(report.byFeature)
    .map(([feature, totals]) => ({ feature, ...totals }))
    .sort((a, b) => b.calls - a.calls || b.estimatedCostUSD - a.estimatedCostUSD);
}
