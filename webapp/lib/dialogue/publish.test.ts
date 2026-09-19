import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { conversationContentHash } from "../tts/content-hash";
import { scenarioLinesToConversation } from "../tts/scenario-conversation";
import {
  isPublishStale,
  publishedAudioUrlLooksMixed,
} from "./publish-audio";

const LINES = [{ speaker: "Aiko", japanese: "すごい！" }];
const HASH = conversationContentHash(
  scenarioLinesToConversation(LINES).lines
);
const VARIANT = "550e8400-e29b-41d4-a716-446655440000";
const DRY = `https://cdn.example.com/dialogue/ball-game/cheer/${HASH}-${VARIANT}.m4a`;
const MIXED = `https://cdn.example.com/dialogue/ball-game/cheer/${HASH}-${VARIANT}-b7c1a9d3e012.m4a`;

describe("publishedAudioUrlLooksMixed", () => {
  it("treats a dry take key as not mixed", () => {
    assert.equal(publishedAudioUrlLooksMixed(DRY), false);
  });

  it("detects the old mix-hash suffix", () => {
    assert.equal(publishedAudioUrlLooksMixed(MIXED), true);
  });
});

describe("isPublishStale", () => {
  const lines = LINES;

  it("flags a leftover baked mix URL", () => {
    assert.equal(
      isPublishStale(
        {
          publishedAudioUrl: MIXED,
          publishedContentHash: HASH,
          publishedAmbienceHash: "b7c1a9d3e012",
          lines,
        },
        "b7c1a9d3e012"
      ),
      true
    );
  });

  it("is current when the dry URL and ambience hash match", () => {
    assert.equal(
      isPublishStale(
        {
          publishedAudioUrl: DRY,
          publishedContentHash: HASH,
          publishedAmbienceHash: null,
          lines,
        },
        null
      ),
      false
    );
  });
});
