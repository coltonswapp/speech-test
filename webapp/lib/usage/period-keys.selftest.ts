/**
 * Quick sanity checks for period key helpers (no test runner in package.json).
 * Run: pnpm exec tsx lib/usage/period-keys.selftest.ts
 */
import {
  isoWeekPartsUTC,
  usagePeriodDocId,
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

// 2025-12-29 is Monday → still ISO week 1 of 2026
const prevYearMon = new Date(Date.UTC(2025, 11, 29));
assert(usagePeriodDocId("week", prevYearMon) === "week_2026-W01", "week year boundary");

console.log("period-keys.selftest: ok");
