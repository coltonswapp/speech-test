import "server-only";

import {
  getFirebaseAdminStatus,
  getUsageFirestore,
} from "@/lib/usage/firebase-admin";
import { parseFeedbackPeriodDoc } from "@/lib/usage/parse-feedback-period";
import {
  mergeUsageWithFeedback,
  parseUsagePeriodDoc,
  type UsagePeriodSnapshot,
} from "@/lib/usage/parse-period";
import {
  PRODUCT_USAGE_SCOPE,
  feedbackPeriodDocPath,
  usagePeriodDocId,
  usagePeriodDocPath,
  type UsagePeriod,
} from "@/lib/usage/period-keys";

export type { UsagePeriodSnapshot };

export class UsageFirestoreError extends Error {
  constructor(
    message: string,
    readonly code: "not_configured" | "read_failed",
  ) {
    super(message);
    this.name = "UsageFirestoreError";
  }
}

async function readDocData(
  path: string,
): Promise<Record<string, unknown> | null> {
  const snap = await getUsageFirestore().doc(path).get();
  return snap.exists ? (snap.data() as Record<string, unknown>) : null;
}

async function readPeriodDoc(
  scope: string,
  period: UsagePeriod,
  at: Date,
): Promise<UsagePeriodSnapshot> {
  const status = getFirebaseAdminStatus();
  if (!status.ok) {
    throw new UsageFirestoreError(status.reason, "not_configured");
  }

  const periodDocId = usagePeriodDocId(period, at);
  const usagePath = usagePeriodDocPath(scope, periodDocId);
  const feedbackPath = feedbackPeriodDocPath(scope, periodDocId);

  try {
    // One get per collection for this scope+period (usage + feedback stats).
    const [usageData, feedbackData] = await Promise.all([
      readDocData(usagePath),
      readDocData(feedbackPath),
    ]);

    const usage = parseUsagePeriodDoc({
      path: usagePath,
      periodDocId,
      data: usageData,
    });
    const feedback = parseFeedbackPeriodDoc({
      path: feedbackPath,
      periodDocId,
      data: feedbackData,
    });

    return mergeUsageWithFeedback(usage, feedback);
  } catch (err) {
    if (err instanceof UsageFirestoreError) throw err;
    const message =
      err instanceof Error ? err.message : "Firestore read failed";
    throw new UsageFirestoreError(message, "read_failed");
  }
}

export async function readProductUsagePeriod(
  period: UsagePeriod,
  at: Date = new Date(),
): Promise<UsagePeriodSnapshot> {
  return readPeriodDoc(PRODUCT_USAGE_SCOPE, period, at);
}

export async function readUserUsagePeriod(
  uid: string,
  period: UsagePeriod,
  at: Date = new Date(),
): Promise<UsagePeriodSnapshot> {
  const trimmed = uid.trim();
  if (!trimmed || trimmed === PRODUCT_USAGE_SCOPE || trimmed.includes("/")) {
    throw new UsageFirestoreError("Invalid uid", "read_failed");
  }
  return readPeriodDoc(trimmed, period, at);
}
