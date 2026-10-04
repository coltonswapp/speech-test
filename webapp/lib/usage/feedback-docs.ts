import "server-only";

import {
  getFirebaseAdminStatus,
  getUsageFirestore,
} from "@/lib/usage/firebase-admin";
import {
  parseFeedbackVoteDoc,
  type FeedbackRating,
  type FeedbackVoteDoc,
} from "@/lib/usage/parse-feedback-doc";
import { UsageFirestoreError } from "@/lib/usage/firestore";

const DEFAULT_LIMIT = 40;
const MAX_LIMIT = 100;

export type ListFeedbackVotesArgs = {
  /** Max docs to return (1–100). Default 40. */
  limit?: number;
  /** Optional rating filter. Requires composite index with createdAt. */
  rating?: FeedbackRating;
};

export type ListFeedbackVotesResult = {
  projectId: string;
  collection: "llmFeedback";
  limit: number;
  rating: FeedbackRating | null;
  docs: FeedbackVoteDoc[];
};

function clampLimit(value: number | undefined): number {
  if (value == null || !Number.isFinite(value)) return DEFAULT_LIMIT;
  return Math.min(MAX_LIMIT, Math.max(1, Math.floor(value)));
}

/**
 * Recent gloss / LLM feedback vote documents from `llmFeedback`.
 * Read-only. Ordered by `createdAt` desc.
 */
export async function listRecentFeedbackVotes(
  args: ListFeedbackVotesArgs = {},
): Promise<ListFeedbackVotesResult> {
  const status = getFirebaseAdminStatus();
  if (!status.ok) {
    throw new UsageFirestoreError(status.reason, "not_configured");
  }

  const limit = clampLimit(args.limit);
  const rating = args.rating ?? null;

  try {
    const db = getUsageFirestore();
    let query = db
      .collection("llmFeedback")
      .orderBy("createdAt", "desc")
      .limit(limit);

    if (rating) {
      query = db
        .collection("llmFeedback")
        .where("rating", "==", rating)
        .orderBy("createdAt", "desc")
        .limit(limit);
    }

    const snap = await query.get();
    const docs: FeedbackVoteDoc[] = [];
    for (const doc of snap.docs) {
      const parsed = parseFeedbackVoteDoc({
        id: doc.id,
        path: `llmFeedback/${doc.id}`,
        data: doc.data() as Record<string, unknown>,
      });
      if (parsed) docs.push(parsed);
    }

    return {
      projectId: status.projectId,
      collection: "llmFeedback",
      limit,
      rating,
      docs,
    };
  } catch (err) {
    if (err instanceof UsageFirestoreError) throw err;
    const message =
      err instanceof Error ? err.message : "Firestore feedback read failed";
    throw new UsageFirestoreError(message, "read_failed");
  }
}
