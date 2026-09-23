import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { derivePublishPipeline } from "./publish-pipeline";

describe("derivePublishPipeline", () => {
  it("is staged when flagged and not published", () => {
    const pipeline = derivePublishPipeline({
      hasFlags: true,
      isPublishedTake: false,
      collectionIsActive: false,
    });
    assert.equal(pipeline.current, "staged");
    assert.equal(pipeline.reached.staged, true);
    assert.equal(pipeline.reached.inDatabase, false);
    assert.equal(pipeline.reached.clientVisible, false);
  });

  it("is in_database when this take is published but lesson is hidden", () => {
    const pipeline = derivePublishPipeline({
      hasFlags: true,
      isPublishedTake: true,
      collectionIsActive: false,
    });
    assert.equal(pipeline.current, "in_database");
    assert.equal(pipeline.reached.inDatabase, true);
    assert.equal(pipeline.reached.clientVisible, false);
  });

  it("is client_visible only when published and lesson is live", () => {
    const pipeline = derivePublishPipeline({
      hasFlags: false,
      isPublishedTake: true,
      collectionIsActive: true,
    });
    assert.equal(pipeline.current, "client_visible");
    assert.equal(pipeline.reached.clientVisible, true);
  });

  it("does not mark client_visible when lesson is live but take is unpublished", () => {
    const pipeline = derivePublishPipeline({
      hasFlags: true,
      isPublishedTake: false,
      collectionIsActive: true,
    });
    assert.equal(pipeline.current, "staged");
    assert.equal(pipeline.reached.clientVisible, false);
  });
});
