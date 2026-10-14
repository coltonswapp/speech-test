import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { STUDIO_SPLIT_MIN_WIDTH_PX } from "./studio-layout";

describe("STUDIO_SPLIT_MIN_WIDTH_PX", () => {
  it("sits above Tesla Model 3/Y landscape CSS widths", () => {
    assert.equal(STUDIO_SPLIT_MIN_WIDTH_PX, 1280);
    // Model 3/Y after the 2025 DPR bump: ~1100–1254 CSS px landscape.
    assert.ok(STUDIO_SPLIT_MIN_WIDTH_PX > 1254);
    // Tesla-adjacent widths we still collapse so the editor keeps the majority.
    for (const width of [768, 900, 1024, 1180]) {
      assert.ok(width < STUDIO_SPLIT_MIN_WIDTH_PX);
    }
  });
});
