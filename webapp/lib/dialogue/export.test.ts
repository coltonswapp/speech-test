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

describe("buildScenarioFile delivery export", () => {
  it("omits Studio-only delivery tags from spoken lines", () => {
    const file = buildScenarioFile(
      baseScenario({
        lines: [
          {
            speaker: "Aiko",
            japanese: "すごい！",
            delivery: "[excited]",
          },
        ],
      })
    );
    const line = file.scenario.lines[0] as {
      speaker: string;
      japanese: string;
      delivery?: string;
    };
    assert.equal(line.speaker, "Aiko");
    assert.equal(line.japanese, "すごい！");
    assert.equal(line.delivery, undefined);
    assert.equal(JSON.stringify(file).includes("delivery"), false);
    assert.equal(JSON.stringify(file).includes("[excited]"), false);
  });
});

describe("buildScenarioFile sourceScript export", () => {
  it("omits Studio-only sourceScript from public/iOS scenario JSON", () => {
    // sourceScript is Studio-only (DB / Content API). ExportableScenario and
    // buildScenarioFile never include it — same rule as spoken `delivery`.
    const file = buildScenarioFile(baseScenario());
    assert.equal("sourceScript" in file, false);
    assert.equal(JSON.stringify(file).includes("sourceScript"), false);

    const collection = collectionFileSchema.parse(
      buildCollectionFile(
        {
          id: "ball-game",
          title: "Ball game",
          subtitle: null,
          sceneImage: null,
          thumbnailUrl: null,
          thumbnailSmallUrl: null,
        },
        [baseScenario()]
      )
    );
    assert.equal(JSON.stringify(collection).includes("sourceScript"), false);
  });
});

describe("buildScenarioFile durationSeconds export", () => {
  it("ships per-scene durationSeconds from the published take", () => {
    const file = buildScenarioFile(baseScenario({ durationSeconds: 56.2 }));
    assert.equal(file.durationSeconds, 56.2);

    const parsed = collectionFileSchema.parse(
      buildCollectionFile(
        {
          id: "ball-game",
          title: "Ball game",
          subtitle: "A short lesson summary for the iOS lesson screen.",
          unitId: "settling-in",
          unitTitle: "Settling In",
          jlptLevel: 4,
          sceneImage: null,
          thumbnailUrl: null,
          thumbnailSmallUrl: null,
        },
        [baseScenario({ durationSeconds: 56.2 })]
      )
    );
    assert.equal(parsed.subtitle, "A short lesson summary for the iOS lesson screen.");
    assert.equal(parsed.unitId, "settling-in");
    assert.equal(parsed.unitTitle, "Settling In");
    assert.equal(parsed.jlptLevel, 4);
    assert.equal(parsed.scenarios[0]?.durationSeconds, 56.2);
  });

  it("omits durationSeconds when missing or non-positive", () => {
    for (const durationSeconds of [null, undefined, 0, -1] as const) {
      const file = buildScenarioFile(baseScenario({ durationSeconds }));
      assert.equal(file.durationSeconds, undefined);
      assert.equal(JSON.stringify(file).includes("durationSeconds"), false);
    }
  });
});

describe("buildCollectionFile subtitle and unit export", () => {
  it("keeps subtitle and omits unit keys when the lesson is unfiled", () => {
    const parsed = collectionFileSchema.parse(
      buildCollectionFile(
        {
          id: "ball-game",
          title: "Ball game",
          subtitle: "Cheer along at the game.",
          unitId: null,
          unitTitle: null,
          jlptLevel: null,
          sceneImage: null,
          thumbnailUrl: null,
          thumbnailSmallUrl: null,
        },
        [baseScenario()]
      )
    );
    assert.equal(parsed.subtitle, "Cheer along at the game.");
    assert.equal(parsed.unitId, undefined);
    assert.equal(parsed.unitTitle, undefined);
    assert.equal(parsed.jlptLevel, undefined);
    const json = JSON.stringify(parsed);
    assert.equal(json.includes("unitId"), false);
    assert.equal(json.includes("unitTitle"), false);
    assert.equal(json.includes("jlptLevel"), false);
    assert.equal(json.includes("premise"), false);
  });
});
