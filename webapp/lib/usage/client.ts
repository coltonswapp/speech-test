import { formatApiError } from "@/lib/api-error";
import type { FeedbackRating, FeedbackVoteDoc } from "@/lib/usage/parse-feedback-doc";
import type { UsagePeriodSnapshot } from "@/lib/usage/parse-period";
import type { UsagePeriod } from "@/lib/usage/period-keys";

export type UsageApiResponse = {
  period: UsagePeriod;
  periodDocId: string;
  configured: boolean;
  configError: string | null;
  credentialSource: string | null;
  projectId: string | null;
  product: UsagePeriodSnapshot;
  user: UsagePeriodSnapshot | null;
};

export type FeedbackVotesApiResponse = {
  configured: boolean;
  configError: string | null;
  credentialSource: string | null;
  projectId: string | null;
  collection: "llmFeedback";
  limit: number;
  rating: FeedbackRating | null;
  docs: FeedbackVoteDoc[];
};

export const usageApi = {
  async get(args: {
    period: UsagePeriod;
    uid?: string;
  }): Promise<UsageApiResponse> {
    const params = new URLSearchParams({ period: args.period });
    const uid = args.uid?.trim();
    if (uid) params.set("uid", uid);

    const res = await fetch(`/api/usage?${params.toString()}`);
    const body = await res.json().catch(() => null);
    if (!res.ok) {
      throw new Error(formatApiError(body, res.status));
    }
    return body as UsageApiResponse;
  },

  async listFeedback(args?: {
    limit?: number;
    rating?: FeedbackRating | "all";
  }): Promise<FeedbackVotesApiResponse> {
    const params = new URLSearchParams();
    if (args?.limit != null) params.set("limit", String(args.limit));
    if (args?.rating && args.rating !== "all") {
      params.set("rating", args.rating);
    }

    const qs = params.toString();
    const res = await fetch(
      qs ? `/api/usage/feedback?${qs}` : "/api/usage/feedback",
    );
    const body = await res.json().catch(() => null);
    if (!res.ok) {
      throw new Error(formatApiError(body, res.status));
    }
    return body as FeedbackVotesApiResponse;
  },
};
