import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { listContentQa } from "@/lib/dialogue/content-qa-store";

/**
 * Studio list of learner-client content QA records.
 * Auth: Studio Google / agent / passphrase (same as other /api/content/*).
 *
 * Query: ?collectionId=train-station
 */
export async function GET(request: NextRequest) {
  const collectionId =
    request.nextUrl.searchParams.get("collectionId")?.trim() || undefined;
  const reviews = await listContentQa(
    collectionId ? { collectionId } : undefined,
  );
  const summary = {
    total: reviews.length,
    pending: reviews.filter((r) => r.status === "pending").length,
    dialogueOnly: reviews.filter((r) => r.status === "dialogue").length,
    quizOnly: reviews.filter((r) => r.status === "quiz").length,
    done: reviews.filter((r) => r.status === "done").length,
    withNotes: reviews.filter((r) => !!r.reviewNote?.trim()).length,
  };
  return NextResponse.json({ reviews, summary });
}
