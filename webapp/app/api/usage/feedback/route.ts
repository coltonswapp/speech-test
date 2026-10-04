import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getFirebaseAdminStatus } from "@/lib/usage/firebase-admin";
import {
  listRecentFeedbackVotes,
} from "@/lib/usage/feedback-docs";
import { UsageFirestoreError } from "@/lib/usage/firestore";
import { FEEDBACK_RATINGS } from "@/lib/usage/parse-feedback-doc";

/**
 * Studio-only recent `llmFeedback` vote documents (read-only).
 *
 * Auth is enforced by `proxy.ts` whenever Studio auth is configured — same
 * pattern as `/api/usage`. No write / delete / vote endpoints.
 */

const querySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).optional(),
  rating: z.enum(FEEDBACK_RATINGS).optional(),
});

export async function GET(request: NextRequest) {
  const parsed = querySchema.safeParse({
    limit: request.nextUrl.searchParams.get("limit") ?? undefined,
    rating: request.nextUrl.searchParams.get("rating") ?? undefined,
  });

  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const status = getFirebaseAdminStatus();
  if (!status.ok) {
    return NextResponse.json({
      configured: false,
      configError: status.reason,
      credentialSource: null,
      projectId: null,
      collection: "llmFeedback",
      limit: parsed.data.limit ?? 40,
      rating: parsed.data.rating ?? null,
      docs: [],
    });
  }

  try {
    const result = await listRecentFeedbackVotes({
      limit: parsed.data.limit,
      rating: parsed.data.rating,
    });

    return NextResponse.json({
      configured: true,
      configError: null,
      credentialSource: status.credentialSource,
      projectId: result.projectId,
      collection: result.collection,
      limit: result.limit,
      rating: result.rating,
      docs: result.docs,
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
      err instanceof Error ? err.message : "Failed to load feedback";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
