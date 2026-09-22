import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  isKaraokeSnapshotStale,
  karaokeSnapshotForTake,
  learnerTokenSyncForPublishedTake,
} from "./publish-lockstep";
import {
  buildScenarioReadiness,
  curriculumSyncStatus,
  curriculumTimingStatus,
} from "./scenario-readiness";
import type { PublishedTokenSync, VariantTokenSync } from "./types";

const HASH = "content-hash";

function spoken(japanese: string) {
  return { speaker: "Aiko", japanese };
}

function workingSync(
  texts: string[],
  times: Array<Array<number | null>>,
): VariantTokenSync {
  return {
    version: 1,
    contentHash: HASH,
    lines: texts.map((text, lineIndex) => ({
      text,
      tokens: text.split("").map((char, tokenIndex) => ({
        text: char,
        startSeconds: times[lineIndex]?.[tokenIndex] ?? null,
      })),
    })),
  };
}

function publishedSync(
  texts: string[],
  times: number[][],
  variantId = "take-1",
): PublishedTokenSync {
  return {
    version: 1,
    variantId,
    contentHash: HASH,
    lines: texts.map((text, lineIndex) => ({
      text,
      tokens: text.split("").map((char, tokenIndex) => ({
        text: char,
        startSeconds: times[lineIndex][tokenIndex],
      })),
    })),
  };
}

const quiz = [
  {
    prompt: "What did they say?",
    layout: "list" as const,
    choices: ["はい", "いいえ"],
    correctChoice: "はい",
    wrongAnswerExplanation: "Listen again.",
  },
];

describe("curriculumSyncStatus", () => {
  it("does not treat studio-only karaoke as published", () => {
    const status = curriculumSyncStatus({
      publishedTokenSync: null,
      workingTokenSync: workingSync(["ab"], [[0.1, 0.3]]),
      contentHash: HASH,
      spokenTexts: ["ab"],
    });
    assert.equal(status, "ready");
  });

  it("is complete only when the published snapshot matches current lines", () => {
    const status = curriculumSyncStatus({
      publishedTokenSync: publishedSync(["ab"], [[0.1, 0.3]]),
      workingTokenSync: workingSync(["ab"], [[0.1, 0.3]]),
      contentHash: HASH,
      spokenTexts: ["ab"],
    });
    assert.equal(status, "complete");
  });

  it("goes stale when published karaoke no longer matches the take", () => {
    const status = curriculumSyncStatus({
      publishedTokenSync: publishedSync(["ab"], [[0.1, 0.3]]),
      workingTokenSync: workingSync(["ab"], [[0.2, 0.4]]),
      contentHash: HASH,
      spokenTexts: ["ab"],
      karaokeStale: true,
    });
    assert.equal(status, "stale");
  });
});

describe("curriculumTimingStatus", () => {
  it("keeps complete studio marks amber until they ship with audio", () => {
    assert.equal(
      curriculumTimingStatus({
        publishedAudio: false,
        audioStale: false,
        publishedMarks: undefined,
        workingMarks: [12000],
        spokenCount: 2,
      }),
      "ready",
    );
  });

  it("is done only when published audio still matches and the published take is timed", () => {
    assert.equal(
      curriculumTimingStatus({
        publishedAudio: true,
        audioStale: false,
        publishedMarks: [12000],
        workingMarks: [12000],
        spokenCount: 2,
      }),
      "done",
    );
    assert.equal(
      curriculumTimingStatus({
        publishedAudio: true,
        audioStale: true,
        publishedMarks: [12000],
        workingMarks: [12000],
        spokenCount: 2,
      }),
      "ready",
    );
  });
});

describe("buildScenarioReadiness lock-step", () => {
  const twoLines = [spoken("ab"), spoken("cd")];

  it("stays mixed-tone when audio published without shipping karaoke", () => {
    const readiness = buildScenarioReadiness({
      publishedAudioUrl: "https://cdn.example/clip.m4a",
      lines: twoLines,
      quiz,
      tokenSync: null,
      publishedMarks: [8000],
      workingMarks: [8000],
      workingTokenSync: workingSync(["ab", "cd"], [
        [0.1, 0.2],
        [0.4, 0.5],
      ]),
      contentHash: HASH,
    });
    assert.equal(readiness.audio, "published");
    assert.equal(readiness.timing, "done");
    assert.equal(readiness.sync, "ready");
    assert.equal(readiness.quiz, "published");
  });

  it("marks the whole package stale when the clip no longer matches lines", () => {
    const readiness = buildScenarioReadiness({
      publishedAudioUrl: "https://cdn.example/clip.m4a",
      audioStale: true,
      lines: twoLines,
      quiz,
      tokenSync: publishedSync(["ab", "cd"], [
        [0.1, 0.2],
        [0.4, 0.5],
      ]),
      publishedMarks: [8000],
      workingMarks: [8000],
      workingTokenSync: workingSync(["ab", "cd"], [
        [0.1, 0.2],
        [0.4, 0.5],
      ]),
      contentHash: HASH,
    });
    assert.equal(readiness.audio, "stale");
    assert.equal(readiness.timing, "ready");
    assert.equal(readiness.quiz, "ready");
  });

  it("keeps quiz amber until a current clip is published", () => {
    const readiness = buildScenarioReadiness({
      publishedAudioUrl: null,
      lines: twoLines,
      quiz,
      tokenSync: null,
      workingMarks: [8000],
      workingTokenSync: workingSync(["ab", "cd"], [
        [0.1, 0.2],
        [0.4, 0.5],
      ]),
      contentHash: HASH,
    });
    assert.equal(readiness.audio, "draft");
    assert.equal(readiness.timing, "ready");
    assert.equal(readiness.sync, "ready");
    assert.equal(readiness.quiz, "ready");
  });
});

describe("karaokeSnapshotForTake", () => {
  it("treats a finished take as stale until that snapshot is published", () => {
    const take = {
      id: "take-1",
      tokenSync: workingSync(["ab"], [[0.1, 0.3]]),
      contentHash: HASH,
      dialogueLineSwitchSamples: null,
      sampleRate: 24000,
      audioByteCount: 44 + 24000 * 2,
      trimSampleLower: 0,
      trimSampleUpper: 24000,
    };
    const next = karaokeSnapshotForTake({
      take,
      lines: [spoken("ab")],
      contentHash: HASH,
    });
    assert.ok(next);
    assert.equal(isKaraokeSnapshotStale(null, next), true);
    assert.equal(isKaraokeSnapshotStale(next, next), false);
  });
});

describe("learnerTokenSyncForPublishedTake", () => {
  const take = {
    id: "take-1",
    tokenSync: workingSync(["ab"], [[0.1, 0.3]]),
    contentHash: HASH,
    dialogueLineSwitchSamples: null,
    sampleRate: 24000,
    audioByteCount: 44 + 24000 * 2,
    trimSampleLower: 0,
    trimSampleUpper: 24000,
  };

  it("fills a null published column from the matching take", () => {
    const sync = learnerTokenSyncForPublishedTake({
      storedTokenSync: null,
      publishedVariantId: "take-1",
      publishedContentHash: HASH,
      take,
      lines: [spoken("ab")],
    });
    assert.equal(sync?.lines[0]?.tokens[1]?.startSeconds, 0.3);
    assert.equal(sync?.variantId, "take-1");
  });

  it("keeps the stored snapshot when the published take no longer matches", () => {
    const stored = publishedSync(["ab"], [[0.1, 0.3]]);
    const sync = learnerTokenSyncForPublishedTake({
      storedTokenSync: stored,
      publishedVariantId: "take-1",
      publishedContentHash: HASH,
      take: {
        ...take,
        contentHash: "other-hash",
        tokenSync: workingSync(["ab"], [[0.5, 0.9]]),
      },
      lines: [spoken("ab")],
    });
    assert.deepEqual(sync, stored);
  });

  it("keeps the stored snapshot when the working copy is not complete", () => {
    const stored = publishedSync(["ab"], [[0.1, 0.3]]);
    const sync = learnerTokenSyncForPublishedTake({
      storedTokenSync: stored,
      publishedVariantId: "take-1",
      publishedContentHash: HASH,
      take: {
        ...take,
        tokenSync: workingSync(["ab"], [[0.1, null]]),
      },
      lines: [spoken("ab")],
    });
    assert.deepEqual(sync, stored);
  });
});
