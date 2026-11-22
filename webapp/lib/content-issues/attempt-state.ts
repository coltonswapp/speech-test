/**
 * Latest-attempt presentation for content issues. Attempts are newest-first.
 * Matches `latestNeedsReview` in clip-agent-attempts.tsx: skip failed/dispatched,
 * then the newest done/working attempt is needs_review only when it is done with
 * that outcome. The report status stays `open`.
 */

export type AttemptSummary = {
  status: string;
  outcome?: string | null;
  finishedAt?: string | null;
};

export type IssueAttemptState = {
  needsReview: boolean;
  agentWorking: boolean;
  agentFinishedAt: string | null;
};

/** Newest done or working attempt; used when that attempt asked for a person's review. */
export function latestReviewAttempt<T extends AttemptSummary>(attempts: T[]): T | null {
  const latest = attempts.find((attempt) => attempt.status === "done" || attempt.status === "working");
  return latest?.status === "done" && latest.outcome === "needs_review" ? latest : null;
}

export function issueAttemptState(attempts: AttemptSummary[]): IssueAttemptState {
  const newest = attempts[0];
  const finished = attempts.find((attempt) => attempt.finishedAt);
  return {
    needsReview: latestReviewAttempt(attempts) != null,
    agentWorking: newest?.status === "dispatched" || newest?.status === "working",
    agentFinishedAt: finished?.finishedAt ?? null,
  };
}

export type TimelineEvent = { label: string; at: string };

/** Compact list-row history: reported, latest agent finish, and when a person closed it. */
export function issueTimelineEvents(input: {
  createdAt?: string | null;
  agentFinishedAt?: string | null;
  resolvedAt?: string | null;
  status?: string | null;
}): TimelineEvent[] {
  const events: TimelineEvent[] = [];
  if (input.createdAt) events.push({ label: "Reported", at: input.createdAt });
  if (input.agentFinishedAt) events.push({ label: "Agent finished", at: input.agentFinishedAt });
  if (input.status && input.status !== "open" && input.resolvedAt) {
    const label =
      input.status === "wontfix" ? "Won’t fix" : input.status === "duplicate" ? "Duplicate" : "Resolved";
    events.push({ label, at: input.resolvedAt });
  }
  return events;
}
