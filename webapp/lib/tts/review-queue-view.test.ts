import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  countTakesByTrack,
  gateAButtonState,
  latestQueuedTakeIds,
  parseReviewJlptTrack,
  reviewQueueTrack,
  takeIsSuperseded,
} from "./review-queue-view";

describe("reviewQueueTrack", () => {
  it("maps 5/4/3 and dumps unfiled onto N5", () => {
    assert.equal(reviewQueueTrack(5), 5);
    assert.equal(reviewQueueTrack(4), 4);
    assert.equal(reviewQueueTrack(3), 3);
    assert.equal(reviewQueueTrack(null), 5);
    assert.equal(reviewQueueTrack(2), 5);
    assert.equal(parseReviewJlptTrack("4"), 4);
    assert.equal(parseReviewJlptTrack("nope"), 5);
  });
});

describe("takeIsSuperseded / latestQueuedTakeIds", () => {
  it("marks a queued take superseded when a newer sibling exists", () => {
    const older = {
      variantId: "v1",
      createdAt: "2026-10-01T10:00:00.000Z",
      siblings: [
        {
          variantId: "v1",
          createdAt: "2026-10-01T10:00:00.000Z",
          takeIndex: 1,
          isPublishedTake: false,
          isSelectedTake: false,
        },
        {
          variantId: "v2",
          createdAt: "2026-10-01T12:00:00.000Z",
          takeIndex: 2,
          isPublishedTake: false,
          isSelectedTake: true,
        },
      ],
    };
    assert.equal(takeIsSuperseded(older), true);
    assert.equal(
      takeIsSuperseded({
        ...older,
        variantId: "v2",
        createdAt: "2026-10-01T12:00:00.000Z",
      }),
      false,
    );
  });

  it("keeps the newest queued take per scene by default", () => {
    const takes = [
      {
        variantId: "old",
        projectId: "p1",
        scenarioId: "lesson/scene-a",
        createdAt: "2026-10-01T10:00:00.000Z",
      },
      {
        variantId: "new",
        projectId: "p1",
        scenarioId: "lesson/scene-a",
        createdAt: "2026-10-01T12:00:00.000Z",
      },
      {
        variantId: "other",
        projectId: "p2",
        scenarioId: "lesson/scene-b",
        createdAt: "2026-10-01T11:00:00.000Z",
      },
    ];
    const ids = latestQueuedTakeIds(takes);
    assert.equal(ids.has("new"), true);
    assert.equal(ids.has("other"), true);
    assert.equal(ids.has("old"), false);
  });
});

describe("gateAButtonState", () => {
  it("is Published when the selected take is already the published one", () => {
    const state = gateAButtonState({
      variantId: "v1",
      isPublishedTake: true,
      isSelectedTake: true,
      siblings: [
        {
          variantId: "v1",
          isPublishedTake: true,
          isSelectedTake: true,
        },
      ],
      timing: { publishedAt: "2026-10-01T12:00:00.000Z" },
    });
    assert.equal(state.kind, "published");
    assert.equal(state.publishedAt, "2026-10-01T12:00:00.000Z");
  });

  it("is Republish when selected and published takes differ", () => {
    const state = gateAButtonState({
      variantId: "v2",
      isPublishedTake: false,
      isSelectedTake: true,
      siblings: [
        {
          variantId: "v1",
          isPublishedTake: true,
          isSelectedTake: false,
        },
        {
          variantId: "v2",
          isPublishedTake: false,
          isSelectedTake: true,
        },
      ],
      scenarioPublishedAt: "2026-09-01T00:00:00.000Z",
    });
    assert.equal(state.kind, "republish");
    assert.equal(state.publishedAt, "2026-09-01T00:00:00.000Z");
  });

  it("is Publish when nothing has landed via Gate A", () => {
    const state = gateAButtonState({
      variantId: "v1",
      isPublishedTake: false,
      isSelectedTake: true,
      siblings: [],
    });
    assert.equal(state.kind, "publish");
    assert.equal(state.publishedAt, null);
  });
});

describe("countTakesByTrack", () => {
  it("counts N5 (including unfiled), N4, and N3", () => {
    const counts = countTakesByTrack([
      { jlptLevel: 5 },
      { jlptLevel: 5 },
      { jlptLevel: 4 },
      { jlptLevel: null },
      { jlptLevel: 3 },
    ]);
    assert.deepEqual(counts, { 5: 3, 4: 1, 3: 1 });
  });
});
