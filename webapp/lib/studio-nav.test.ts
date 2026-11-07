import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  STUDIO_MORE_NAV,
  STUDIO_NAV_ITEMS,
  STUDIO_PRIMARY_NAV,
  activeNavIndex,
  computeVisiblePrimaryIndices,
  matchesPath,
} from "./studio-nav";

describe("studio nav destinations", () => {
  it("keeps everyday content plus Generate in the primary bar", () => {
    assert.deepEqual(
      STUDIO_PRIMARY_NAV.map((item) => item.label),
      [
        "Dialogues",
        "Curriculum",
        "Slides",
        "Grammar",
        "Generate",
        "Review queue",
      ],
    );
  });

  it("parks secondary tools under More without dropping routes", () => {
    assert.deepEqual(
      STUDIO_MORE_NAV.map((item) => [item.label, item.href]),
      [
        ["Patterns", "/content/patterns"],
        ["Coverage", "/content/coverage"],
        ["Ambience", "/tts/ambience"],
        ["TTS Studio", "/tts"],
        ["Usage", "/usage"],
        ["Settings", "/settings"],
      ],
    );
    const hrefs = STUDIO_NAV_ITEMS.map((item) => item.href);
    assert.equal(new Set(hrefs).size, hrefs.length);
  });
});

describe("matchesPath", () => {
  it("does not treat Grammar as Dialogues or Patterns", () => {
    assert.equal(matchesPath("/content", "/content"), true);
    assert.equal(matchesPath("/content/dialogues", "/content"), false);
    assert.equal(matchesPath("/content/patterns", "/content"), false);
    assert.equal(matchesPath("/content/some-point", "/content"), true);
  });

  it("keeps TTS sub-routes on their own items", () => {
    assert.equal(matchesPath("/tts/review", "/tts/review"), true);
    assert.equal(matchesPath("/tts/review", "/tts"), true);
    assert.equal(matchesPath("/tts/ambience", "/tts/ambience"), true);
    assert.equal(matchesPath("/tts/abc", "/tts"), true);
    assert.equal(matchesPath("/tts/abc", "/tts/review"), false);
  });

  it("prefers the more specific TTS routes when resolving the active item", () => {
    assert.equal(
      STUDIO_NAV_ITEMS[activeNavIndex("/tts/review")]?.label,
      "Review queue",
    );
    assert.equal(
      STUDIO_NAV_ITEMS[activeNavIndex("/tts/ambience")]?.label,
      "Ambience",
    );
    assert.equal(STUDIO_NAV_ITEMS[activeNavIndex("/tts")]?.label, "TTS Studio");
    assert.equal(
      STUDIO_NAV_ITEMS[activeNavIndex("/generate")]?.label,
      "Generate",
    );
  });
});

describe("computeVisiblePrimaryIndices", () => {
  const widths = [80, 90, 70, 80, 90, 110];
  const more = 70;
  const gap = 8;

  it("shows every primary item when the bar is wide enough", () => {
    const result = computeVisiblePrimaryIndices(widths, more, gap, 2000, 0);
    assert.deepEqual(result.visible, [0, 1, 2, 3, 4, 5]);
    assert.deepEqual(result.overflow, []);
  });

  it("always reserves the More control and keeps the active primary visible", () => {
    const result = computeVisiblePrimaryIndices(widths, more, gap, 280, 4);
    assert.ok(result.visible.includes(4));
    assert.ok(result.overflow.length > 0);
    assert.ok(!result.visible.includes(5) || result.visible.includes(4));
  });

  it("can overflow the active item when even it plus More cannot fit with others", () => {
    const result = computeVisiblePrimaryIndices([400, 400], more, gap, 120, 1);
    assert.deepEqual(result.visible, []);
    assert.deepEqual(result.overflow, [0, 1]);
  });
});
