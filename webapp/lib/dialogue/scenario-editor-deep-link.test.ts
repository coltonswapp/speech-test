import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  READINESS_CHIP_TAB,
  readinessChipHref,
  scenarioEditorDeepLink,
  SCENARIO_EDITOR_SECTION_IDS,
  type ReadinessChipKey,
} from "./scenario-editor-deep-link";

function expandedOf(collapsed: readonly string[]): string[] {
  return SCENARIO_EDITOR_SECTION_IDS.filter((id) => !collapsed.includes(id));
}

describe("scenarioEditorDeepLink", () => {
  it("keeps remembered defaults on a normal visit (no tab, not from review)", () => {
    assert.equal(scenarioEditorDeepLink({ tab: null }), null);
    assert.equal(scenarioEditorDeepLink({ tab: null, fromReview: false }), null);
    assert.equal(scenarioEditorDeepLink({ tab: "raw" }), null);
    assert.equal(scenarioEditorDeepLink({ tab: "source" }), null);
    assert.equal(scenarioEditorDeepLink({ tab: "not-a-section" }), null);
  });

  it("collapses every section except the ?tab= target", () => {
    for (const tab of SCENARIO_EDITOR_SECTION_IDS) {
      const deep = scenarioEditorDeepLink({ tab });
      assert.ok(deep);
      assert.equal(deep.keepOpen, tab);
      assert.deepEqual(expandedOf(deep.collapsed), [tab]);
    }
  });

  it("review-queue with no tab keeps only audio open", () => {
    const deep = scenarioEditorDeepLink({ tab: null, fromReview: true });
    assert.ok(deep);
    assert.equal(deep.keepOpen, "audio");
    assert.deepEqual(expandedOf(deep.collapsed), ["audio"]);
  });

  it("review-queue still honors an explicit section tab", () => {
    const deep = scenarioEditorDeepLink({ tab: "quiz", fromReview: true });
    assert.ok(deep);
    assert.equal(deep.keepOpen, "quiz");
    assert.deepEqual(expandedOf(deep.collapsed), ["quiz"]);
  });
});

describe("readiness chips → exclusive section", () => {
  const chips: Array<{
    chip: ReadinessChipKey;
    tab: (typeof READINESS_CHIP_TAB)[ReadinessChipKey];
  }> = [
    { chip: "audio", tab: "audio" },
    { chip: "align", tab: "audio" },
    { chip: "review", tab: "audio" },
    { chip: "published", tab: "audio" },
    { chip: "quiz", tab: "quiz" },
    { chip: "thumbnail", tab: "overview" },
    { chip: "contentQa", tab: "overview" },
  ];

  it("each chip deep-links to one section and leaves Lines collapsed", () => {
    const hrefBase = "/content/dialogues/col/scene";
    for (const { chip, tab } of chips) {
      assert.equal(READINESS_CHIP_TAB[chip], tab);
      assert.equal(readinessChipHref(hrefBase, chip), `${hrefBase}?tab=${tab}`);

      const deep = scenarioEditorDeepLink({ tab });
      assert.ok(deep, `missing deep link for chip ${chip}`);
      assert.equal(deep.keepOpen, tab);
      assert.deepEqual(expandedOf(deep.collapsed), [tab]);
      assert.ok(
        deep.collapsed.includes("lines"),
        `${chip} should collapse Lines`,
      );
    }
  });
});
