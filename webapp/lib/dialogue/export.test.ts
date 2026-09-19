import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { collectionFileSchema } from "./types";
import {
  buildCollectionFile,
  buildScenarioFile,
  type ExportableScenario,
} from "./export";

function baseScenario(
  extras: Partial<ExportableScenario> = {}
): ExportableScenario {
  return {
    id: "ball-game/cheer",
    orderIndex: 0,
    menuTitle: "Cheer",
    menuSubtitle: null,
    japanese: "すごい！",
    romaji: "sugoi!",
    english: "Amazing!",
    targetSubstring: null,
    audioKey: "ball-game/cheer",
    publishedAudioUrl: "https://cdn.example.com/dialogue/ball-game/cheer/abc-def.m4a",
    publishedVariantId: "11111111-1111-1111-1111-111111111111",
    publishedContentHash: "a".repeat(64),
    publishedAt: "2026-09-18T00:00:00.000Z",
    grammarPointIds: [],
    setting: "At the ball game",
    thumbnailUrl: null,
    thumbnailSmallUrl: null,
    lines: [{ speaker: "Aiko", japanese: "すごい！" }],
    highlights: null,
    quiz: null,
    tokenSync: null,
    ...extras,
  };
}

describe("buildScenarioFile ambience export", () => {
  it("keeps dialogue audio dry and ships bed id, url, and gain", () => {
    const dryUrl = "https://cdn.example.com/dialogue/ball-game/cheer/abc-def.m4a";
    const file = buildScenarioFile(
      baseScenario({
        publishedAudioUrl: dryUrl,
        ambienceId: "22222222-2222-2222-2222-222222222222",
        ambienceUrl: "https://cdn.example.com/ambience/22222222-2222-2222-2222-222222222222.m4a",
        ambienceGainDb: -22,
      })
    );

    assert.equal(file.publishedAudioUrl, dryUrl);
    assert.equal(file.ambienceId, "22222222-2222-2222-2222-222222222222");
    assert.equal(
      file.ambienceUrl,
      "https://cdn.example.com/ambience/22222222-2222-2222-2222-222222222222.m4a"
    );
    assert.equal(file.ambienceGainDb, -22);

    const parsed = collectionFileSchema.parse(
      buildCollectionFile(
        {
          id: "ball-game",
          title: "Ball game",
          subtitle: null,
          sceneImage: null,
          thumbnailUrl: null,
          thumbnailSmallUrl: null,
        },
        [
          baseScenario({
            publishedAudioUrl: dryUrl,
            ambienceId: "22222222-2222-2222-2222-222222222222",
            ambienceUrl:
              "https://cdn.example.com/ambience/22222222-2222-2222-2222-222222222222.m4a",
            ambienceGainDb: -22,
          }),
        ]
      )
    );
    assert.equal(parsed.scenarios[0]?.publishedAudioUrl, dryUrl);
    assert.equal(parsed.scenarios[0]?.ambienceId, "22222222-2222-2222-2222-222222222222");
    assert.equal(
      parsed.scenarios[0]?.ambienceUrl,
      "https://cdn.example.com/ambience/22222222-2222-2222-2222-222222222222.m4a"
    );
    assert.equal(parsed.scenarios[0]?.ambienceGainDb, -22);
  });

  it("omits ambience keys when the scene has no bed", () => {
    const file = buildScenarioFile(baseScenario());
    assert.equal(file.ambienceId, undefined);
    assert.equal(file.ambienceUrl, undefined);
    assert.equal(file.ambienceGainDb, undefined);
    const json = JSON.stringify(file);
    assert.equal(json.includes("ambienceId"), false);
    assert.equal(json.includes("ambienceUrl"), false);
    assert.equal(json.includes("ambienceGainDb"), false);
  });
});
