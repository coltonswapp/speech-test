import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { pickWashPhoto, scatterForSlide } from "./scatter";

const photos = [
  { id: "a", url: "/a.jpg" },
  { id: "b", url: "/b.jpg" },
  { id: "c", url: "/c.jpg" },
  { id: "d", url: "/d.jpg" },
];

describe("scatterForSlide", () => {
  it("is stable for the same seed and slide", () => {
    const first = scatterForSlide({ photos, seed: 42, slideIndex: 0, count: 4 });
    const second = scatterForSlide({ photos, seed: 42, slideIndex: 0, count: 4 });
    assert.deepEqual(first, second);
  });

  it("differs across slides", () => {
    const a = scatterForSlide({ photos, seed: 42, slideIndex: 0, count: 4 });
    const b = scatterForSlide({ photos, seed: 42, slideIndex: 1, count: 4 });
    assert.notDeepEqual(a, b);
  });

  it("sizes tiles to cover most of the frame", () => {
    const pieces = scatterForSlide({ photos, seed: 42, slideIndex: 0, count: 4 });
    assert.equal(pieces.length, 4);
    for (const piece of pieces) {
      assert.ok(piece.width >= 88);
      assert.ok(piece.height >= 88);
    }
  });
});

describe("pickWashPhoto", () => {
  it("picks a photo from the pool", () => {
    const photo = pickWashPhoto(photos, 7, 0);
    assert.ok(photo);
    assert.ok(photos.some((row) => row.id === photo.id));
  });
});
