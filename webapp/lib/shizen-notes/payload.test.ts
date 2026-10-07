import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  SCREENSHOT_URL_INSTRUCTIONS,
  screenshotObjectKey,
  shoheiDeliveryPayload,
  type ShoheiNoteJob,
} from "./payload";
import { noteValidationReason, shizenNoteSchema } from "./schema";

const TINY_JPEG =
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAABAAEDAREAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAj/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGf/9k=";

const SIGNED_URL =
  "https://example.r2.cloudflarestorage.com/bucket/shizen-notes/job_test-abc.jpg?X-Amz-Expires=259200&X-Amz-Signature=deadbeef";

const job: ShoheiNoteJob = {
  id: "job_test",
  source: "dialogue",
  sourceId: "train-station/buying-a-ticket",
  title: "Dialogue",
  note: "The button label is wrong.",
  agent: "shohei",
  url: "https://studio.example/content/dialogues/train-station/buying-a-ticket",
  noteCreatedAt: new Date("2026-10-06T18:00:00.000Z"),
};

function noteBody(screenshot?: string) {
  return {
    source: "dialogue",
    source_id: "train-station/buying-a-ticket",
    note: "The button label is wrong.",
    metadata: {
      url: "https://studio.example/scene",
      created_at: "2026-10-06T18:00:00.000Z",
      ...(screenshot ? { screenshot_jpeg: screenshot } : {}),
    },
  };
}

describe("shoheiDeliveryPayload", () => {
  it("omits screenshot fields when the job has no image", () => {
    const payload = shoheiDeliveryPayload(job, null);
    assert.deepEqual(payload.metadata, {
      url: "https://studio.example/content/dialogues/train-station/buying-a-ticket",
      created_at: "2026-10-06T18:00:00.000Z",
    });
  });

  it("sends a signed link and download instructions, never inline bytes", () => {
    const payload = shoheiDeliveryPayload(job, SIGNED_URL);
    assert.equal(payload.metadata.screenshot_url, SIGNED_URL);
    assert.equal(payload.metadata.screenshot_instructions, SCREENSHOT_URL_INSTRUCTIONS);
    assert.match(SCREENSHOT_URL_INSTRUCTIONS, /curl -fsSL -o screenshot\.jpg/);
    assert.equal("screenshot_jpeg" in payload.metadata, false);
    assert.ok(JSON.stringify(payload).length < 2_000);
  });
});

describe("screenshotObjectKey", () => {
  it("namespaces by job and keeps the random suffix", () => {
    assert.equal(screenshotObjectKey("job_abc", "r4nd0m"), "shizen-notes/job_abc-r4nd0m.jpg");
  });
});

describe("shizenNoteSchema screenshot_jpeg", () => {
  it("accepts a note with no screenshot", () => {
    const parsed = shizenNoteSchema.safeParse(noteBody());
    assert.equal(parsed.success, true);
    if (parsed.success) assert.equal(parsed.data.metadata.screenshot_jpeg, undefined);
  });

  it("accepts a base64 JPEG and rejects other payloads", () => {
    assert.equal(shizenNoteSchema.safeParse(noteBody(TINY_JPEG)).success, true);

    const png = shizenNoteSchema.safeParse(noteBody("iVBORw0KGgo="));
    assert.equal(png.success, false);
    if (!png.success) {
      assert.equal(noteValidationReason(png.error, noteBody("iVBORw0KGgo=")), "bad screenshot_jpeg");
    }
  });
});
