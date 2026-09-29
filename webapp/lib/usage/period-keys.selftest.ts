/**
 * Quick sanity checks for period key helpers (no test runner in package.json).
 * Run: pnpm exec tsx lib/usage/period-keys.selftest.ts
 */
import {
  feedbackPeriodDocPath,
  isoWeekPartsUTC,
  usagePeriodDocId,
  usagePeriodDocPath,
  usagePeriodKey,
} from "./period-keys";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

const day = new Date(Date.UTC(2026, 2, 25)); // 2026-03-25 Wed
assert(usagePeriodKey("day", day) === "2026-03-25", "day key");
assert(usagePeriodDocId("day", day) === "day_2026-03-25", "day doc id");
assert(usagePeriodKey("month", day) === "2026-03", "month key");
assert(usagePeriodDocId("month", day) === "month_2026-03", "month doc id");

// 2026-01-01 is Thursday → ISO week 1 of 2026
const weekStart = new Date(Date.UTC(2026, 0, 1));
const parts = isoWeekPartsUTC(weekStart);
assert(parts.year === 2026 && parts.week === 1, `iso week got ${parts.year}-W${parts.week}`);
assert(usagePeriodDocId("week", weekStart) === "week_2026-W01", "week doc id");

// 2025-12-29 is Monday → still ISO week 1 of 2026 (Mon–Sun UTC week)
const prevYearMon = new Date(Date.UTC(2025, 11, 29));
assert(usagePeriodDocId("week", prevYearMon) === "week_2026-W01", "week year boundary");

// Same ISO week: Monday 2026-03-23 through Sunday 2026-03-29 → week_2026-W13
const week13Mon = new Date(Date.UTC(2026, 2, 23));
const week13Sun = new Date(Date.UTC(2026, 2, 29));
assert(usagePeriodDocId("week", week13Mon) === "week_2026-W13", "ISO week Mon");
assert(usagePeriodDocId("week", week13Sun) === "week_2026-W13", "ISO week Sun");
// Adjacent Sunday/Monday cross the week boundary
assert(usagePeriodDocId("week", new Date(Date.UTC(2026, 2, 22))) === "week_2026-W12", "prior Sun");
assert(usagePeriodDocId("week", new Date(Date.UTC(2026, 2, 30))) === "week_2026-W14", "next Mon");

assert(
  usagePeriodDocPath("_product", "day_2026-03-25") ===
    "llmUsage/_product/periods/day_2026-03-25",
  "usage path",
);
assert(
  feedbackPeriodDocPath("_product", "day_2026-03-25") ===
    "llmFeedbackStats/_product/periods/day_2026-03-25",
  "feedback path",
);
assert(
  feedbackPeriodDocPath("kYqKbEEc5FUmN2vLEWL3x9NRSVe2", "week_2026-W13") ===
    "llmFeedbackStats/kYqKbEEc5FUmN2vLEWL3x9NRSVe2/periods/week_2026-W13",
  "feedback per-uid path",
);

console.log("period-keys.selftest: ok");
