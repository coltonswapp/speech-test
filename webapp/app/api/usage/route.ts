import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getFirebaseAdminStatus } from "@/lib/usage/firebase-admin";
import {
  readProductUsagePeriod,
  readUserUsagePeriod,
  UsageFirestoreError,
} from "@/lib/usage/firestore";
import { parseUsagePeriodDoc } from "@/lib/usage/parse-period";
import {
  isUsagePeriod,
  PRODUCT_USAGE_SCOPE,
  usagePeriodDocId,
  usagePeriodDocPath,
} from "@/lib/usage/period-keys";

/**
 * Studio-only LLM usage aggregates (read-only).
 *
 * Auth is enforced by `proxy.ts` whenever Studio auth is configured — same
 * pattern as Settings/TTS APIs. Credentials stay server-side; there is no
 * learner-facing cross-uid lookup via the LLM gateway.
 */

const querySchema = z.object({
  period: z.string().refine(isUsagePeriod, {
    message: "period must be day, week, or month",
  }),
  uid: z
    .string()
    .trim()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, "uid must be alphanumeric")
    .optional(),
});

function emptySnapshot(scope: string, periodDocId: string) {
  return parseUsagePeriodDoc({
    path: usagePeriodDocPath(scope, periodDocId),
    periodDocId,
    data: null,
  });
}

export async function GET(request: NextRequest) {
  const parsed = querySchema.safeParse({
    period: request.nextUrl.searchParams.get("period") ?? undefined,
    uid: request.nextUrl.searchParams.get("uid") ?? undefined,
  });

  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const { period, uid } = parsed.data;
  const periodDocId = usagePeriodDocId(period);
  const status = getFirebaseAdminStatus();

  if (!status.ok) {
    return NextResponse.json({
      period,
      periodDocId,
      configured: false,
      configError: status.reason,
      credentialSource: null,
      projectId: null,
      product: emptySnapshot(PRODUCT_USAGE_SCOPE, periodDocId),
      user: uid ? emptySnapshot(uid, periodDocId) : null,
    });
  }

  try {
    const product = await readProductUsagePeriod(period);
    const user = uid ? await readUserUsagePeriod(uid, period) : null;

    return NextResponse.json({
      period,
      periodDocId,
      configured: true,
      configError: null,
      credentialSource: status.credentialSource,
      projectId: status.projectId,
      product,
      user,
    });
  } catch (err) {
    if (err instanceof UsageFirestoreError) {
      const statusCode = err.code === "not_configured" ? 503 : 502;
      return NextResponse.json(
        { error: err.message, code: err.code },
        { status: statusCode },
      );
    }
    const message =
      err instanceof Error ? err.message : "Failed to load usage";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
