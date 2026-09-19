import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  ambienceKindLabel,
  ambienceMixFilterComplex,
  ambienceMixKeyParts,
  clampAmbienceGainDb,
  clampAmbienceWindow,
  createAmbienceLayer,
  DEFAULT_AMBIENCE_GAIN_DB,
  gainDbToLinear,
  groupAmbienceAssets,
  layersFromScenario,
  normalizeAmbienceKind,
  wrapAmbienceOffset,
} from "./ambience";

describe("normalizeAmbienceKind", () => {
  it("keeps preset slugs", () => {
    assert.equal(normalizeAmbienceKind("Cafe"), "cafe");
    assert.equal(normalizeAmbienceKind("station"), "station");
  });

  it("slugifies a custom type", () => {
    assert.equal(normalizeAmbienceKind("Rain on glass"), "rain-on-glass");
    assert.equal(normalizeAmbienceKind("  Office HVAC  "), "office-hvac");
  });

  it("falls back to other when empty", () => {
    assert.equal(normalizeAmbienceKind("   "), "other");
    assert.equal(normalizeAmbienceKind("!!!"), "other");
  });
});

describe("ambienceKindLabel", () => {
  it("uses preset labels and title-cases custom slugs", () => {
    assert.equal(ambienceKindLabel("cafe"), "Cafe");
    assert.equal(ambienceKindLabel("rain-on-glass"), "Rain On Glass");
  });
});

describe("groupAmbienceAssets", () => {
  it("lists custom types after presets", () => {
    const groups = groupAmbienceAssets([
      { kind: "rain-on-glass", id: "1" },
      { kind: "cafe", id: "2" },
    ]);
    assert.deepEqual(
      groups.map((group) => group.kind),
      ["cafe", "rain-on-glass"]
    );
  });
});

describe("wrapAmbienceOffset", () => {
  it("wraps past the end of the bed back to the start", () => {
    assert.equal(wrapAmbienceOffset(32, 30), 2);
    assert.equal(wrapAmbienceOffset(30, 30), 0);
    assert.equal(wrapAmbienceOffset(0, 30), 0);
  });

  it("wraps negative shifts forward", () => {
    assert.equal(wrapAmbienceOffset(-2, 30), 28);
  });

  it("returns 0 when duration is missing", () => {
    assert.equal(wrapAmbienceOffset(0, 0), 0);
    assert.equal(wrapAmbienceOffset(4, -1), 4);
  });
});

describe("clampAmbienceGainDb", () => {
  it("keeps beds in the under-dialogue range", () => {
    assert.equal(clampAmbienceGainDb(-22), -22);
    assert.equal(clampAmbienceGainDb(0), -6);
    assert.equal(clampAmbienceGainDb(-80), -36);
    assert.equal(clampAmbienceGainDb(Number.NaN), DEFAULT_AMBIENCE_GAIN_DB);
  });
});

describe("gainDbToLinear", () => {
  it("converts −22 dB to a quiet bed", () => {
    const linear = gainDbToLinear(-22);
    assert.ok(linear > 0.07 && linear < 0.09);
  });
});

describe("ambienceMixKeyParts", () => {
  it("changes when offset, gain, or asset change", () => {
    const base = {
      assetId: "abc",
      gainDb: -22,
      offsetSeconds: 4,
    };
    const a = ambienceMixKeyParts(base);
    assert.notEqual(a, ambienceMixKeyParts({ ...base, offsetSeconds: 6 }));
    assert.notEqual(a, ambienceMixKeyParts({ ...base, gainDb: -18 }));
    assert.notEqual(a, ambienceMixKeyParts({ ...base, assetId: "def" }));
  });
});

describe("ambienceMixFilterComplex", () => {
  it("loops from offset and ducks under speech", () => {
    const graph = ambienceMixFilterComplex({
      durationSeconds: 12,
      gainDb: -22,
      offsetSeconds: 4.5,
    });
    assert.match(graph, /atrim=start=4\.5:duration=12/);
    assert.match(graph, /sidechaincompress/);
    assert.match(graph, /duration=first/);
    assert.match(graph, /afade=t=in/);
    assert.match(graph, /afade=t=out:st=11\.6/);
  });

  it("can skip ducking", () => {
    const graph = ambienceMixFilterComplex({
      durationSeconds: 8,
      gainDb: -20,
      offsetSeconds: 0,
      duck: false,
    });
    assert.doesNotMatch(graph, /sidechaincompress/);
    assert.match(graph, /\[speech\]\[bed\]amix/);
  });

  it("places a windowed layer with delay", () => {
    const graph = ambienceMixFilterComplex({
      durationSeconds: 20,
      layers: [
        {
          gainDb: -22,
          offsetSeconds: 1,
          startSeconds: 8,
          endSeconds: 12,
        },
      ],
    });
    assert.match(graph, /atrim=start=1:duration=4/);
    assert.match(graph, /adelay=8000:all=1/);
    assert.match(graph, /apad=whole_dur=20/);
  });

  it("mixes two beds before ducking speech", () => {
    const graph = ambienceMixFilterComplex({
      durationSeconds: 10,
      layers: [
        { gainDb: -22, offsetSeconds: 0, startSeconds: 0, endSeconds: null },
        { gainDb: -18, offsetSeconds: 2, startSeconds: 4, endSeconds: 7 },
      ],
    });
    assert.match(graph, /\[1:a\]/);
    assert.match(graph, /\[2:a\]/);
    assert.match(graph, /amix=inputs=2:duration=first/);
    assert.match(graph, /sidechaincompress/);
  });
});

describe("layersFromScenario", () => {
  it("prefers json layers over the legacy single bed", () => {
    const layers = layersFromScenario({
      ambienceAssetId: "legacy",
      ambienceGainDb: -22,
      ambienceOffsetSeconds: 0,
      ambienceLayers: [
        {
          id: "a",
          assetId: "rain",
          gainDb: -18,
          offsetSeconds: 1,
          startSeconds: 4,
          endSeconds: 8,
        },
      ],
    });
    assert.equal(layers.length, 1);
    assert.equal(layers[0].assetId, "rain");
    assert.equal(layers[0].startSeconds, 4);
    assert.equal(layers[0].endSeconds, 8);
  });

  it("rebuilds a full-span layer from the single-bed columns", () => {
    const layers = layersFromScenario({
      ambienceAssetId: "cafe",
      ambienceGainDb: -20,
      ambienceOffsetSeconds: 3,
    });
    assert.equal(layers.length, 1);
    assert.equal(layers[0].assetId, "cafe");
    assert.equal(layers[0].startSeconds, 0);
    assert.equal(layers[0].endSeconds, null);
  });
});

describe("clampAmbienceWindow", () => {
  it("treats a window that reaches the take end as open", () => {
    const window = clampAmbienceWindow(2, 9.99, 10);
    assert.equal(window.startSeconds, 2);
    assert.equal(window.endSeconds, null);
  });
});

describe("createAmbienceLayer", () => {
  it("adds extra beds as a short window at the playhead", () => {
    const layer = createAmbienceLayer({
      assetId: "door",
      bedDuration: 12,
      takeDuration: 30,
      playheadSeconds: 10,
      full: false,
    });
    assert.equal(layer.startSeconds, 10);
    assert.equal(layer.endSeconds, 16);
  });
});
