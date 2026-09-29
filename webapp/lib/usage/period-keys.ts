/**
 * Period document IDs for `llmUsage/{scope}/periods/{periodId}`.
 *
 * Writers are not in this repo yet. Studio and any future llm-gateway must
 * agree on these formats (UTC):
 *
 * - day:   `day_YYYY-MM-DD`   (ISO calendar date)
 * - week:  `week_YYYY-Www`    (ISO week-numbering year + week, e.g. `week_2026-W13`)
 * - month: `month_YYYY-MM`    (calendar month)
 */

export const USAGE_PERIODS = ["day", "week", "month"] as const;

export type UsagePeriod = (typeof USAGE_PERIODS)[number];

export function isUsagePeriod(value: string): value is UsagePeriod {
  return (USAGE_PERIODS as readonly string[]).includes(value);
}

/** ISO week-numbering year + week for a UTC instant. */
export function isoWeekPartsUTC(date: Date): { year: number; week: number } {
  const d = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
  // Thursday of this week determines the ISO week-year.
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const year = d.getUTCFullYear();
  const yearStart = new Date(Date.UTC(year, 0, 1));
  const week = Math.ceil(
    ((d.getTime() - yearStart.getTime()) / 86_400_000 + 1) / 7,
  );
  return { year, week };
}

/** Calendar key only (no `day_` / `week_` / `month_` prefix). */
export function usagePeriodKey(
  period: UsagePeriod,
  date: Date = new Date(),
): string {
  switch (period) {
    case "day":
      return date.toISOString().slice(0, 10);
    case "week": {
      const { year, week } = isoWeekPartsUTC(date);
      return `${year}-W${String(week).padStart(2, "0")}`;
    }
    case "month":
      return date.toISOString().slice(0, 7);
  }
}

/** Full Firestore period document id: `{period}_{key}`. */
export function usagePeriodDocId(
  period: UsagePeriod,
  date: Date = new Date(),
): string {
  return `${period}_${usagePeriodKey(period, date)}`;
}

export const PRODUCT_USAGE_SCOPE = "_product";

export function usagePeriodDocPath(scope: string, periodDocId: string): string {
  return `llmUsage/${scope}/periods/${periodDocId}`;
}
