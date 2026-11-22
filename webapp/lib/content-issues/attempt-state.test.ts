import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { issueAttemptState, issueTimelineEvents, latestReviewAttempt } from "./attempt-state";

const attempt = (
  status: string,
  extra: { outcome?: string | null; finishedAt?: string | null } = {},
) => ({ status, outcome: extra.outcome ?? null, finishedAt: extra.finishedAt ?? null });

describe("latestReviewAttempt", () => {
  it("is the newest done/working attempt when that attempt needs review", () => {
    const review = attempt("done", { outcome: "needs_review", finishedAt: "2026-11-22T00:48:00.000Z" });
    assert.equal(
      latestReviewAttempt([attempt("failed"), review, attempt("done", { outcome: "could_not_fix" })]),
      review,
    );
  });

  it("is null when a newer working attempt is in progress, or the latest finish did not ask for review", () => {
    assert.equal(
      latestReviewAttempt([
        attempt("working"),
        attempt("done", { outcome: "needs_review" }),
      ]),
      null,
    );
    assert.equal(latestReviewAttempt([attempt("done", { outcome: "could_not_fix" })]), null);
    assert.equal(latestReviewAttempt([]), null);
  });

  it("skips a newer dispatched attempt so a previous needs_review still shows", () => {
    const review = attempt("done", { outcome: "needs_review" });
    assert.equal(latestReviewAttempt([attempt("dispatched"), review]), review);
  });
});

describe("issueAttemptState", () => {
  it("flags needs review, agent working, and the latest finish time", () => {
    assert.deepEqual(
      issueAttemptState([
        attempt("done", { outcome: "needs_review", finishedAt: "2026-11-22T00:48:00.000Z" }),
      ]),
      {
        needsReview: true,
        agentWorking: false,
        agentFinishedAt: "2026-11-22T00:48:00.000Z",
      },
    );
    assert.deepEqual(issueAttemptState([attempt("working")]), {
      needsReview: false,
      agentWorking: true,
      agentFinishedAt: null,
    });
    assert.deepEqual(issueAttemptState([attempt("dispatched")]), {
      needsReview: false,
      agentWorking: true,
      agentFinishedAt: null,
    });
  });
});

describe("issueTimelineEvents", () => {
  it("builds reported, agent finished, and closed segments", () => {
    assert.deepEqual(
      issueTimelineEvents({
        createdAt: "2026-11-21T10:00:00.000Z",
        agentFinishedAt: "2026-11-22T00:48:00.000Z",
        resolvedAt: "2026-11-22T01:05:00.000Z",
        status: "resolved",
      }),
      [
        { label: "Reported", at: "2026-11-21T10:00:00.000Z" },
        { label: "Agent finished", at: "2026-11-22T00:48:00.000Z" },
        { label: "Resolved", at: "2026-11-22T01:05:00.000Z" },
      ],
    );
    assert.deepEqual(
      issueTimelineEvents({
        createdAt: "2026-11-21T10:00:00.000Z",
        resolvedAt: "2026-11-22T01:05:00.000Z",
        status: "wontfix",
      }),
      [
        { label: "Reported", at: "2026-11-21T10:00:00.000Z" },
        { label: "Won’t fix", at: "2026-11-22T01:05:00.000Z" },
      ],
    );
  });

  it("omits a close time while the report is still open", () => {
    assert.deepEqual(
      issueTimelineEvents({
        createdAt: "2026-11-21T10:00:00.000Z",
        resolvedAt: "2026-11-22T01:05:00.000Z",
        status: "open",
      }),
      [{ label: "Reported", at: "2026-11-21T10:00:00.000Z" }],
    );
  });
});
