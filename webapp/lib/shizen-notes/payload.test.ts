import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  SCREENSHOT_JPEG_INSTRUCTIONS,
  shoheiDeliveryPayload,
  type ShoheiNoteJob,
} from "./payload";
import { noteValidationReason, shizenNoteSchema } from "./schema";

const TINY_JPEG =
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAABAAEDAREAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAj/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGf/9k=";

function job(screenshotJpeg: string | null): ShoheiNoteJob {
  return {
    id: "job_test",
    source: "dialogue",
    sourceId: "train-station/buying-a-ticket",
    title: "Dialogue",
    note: "The button label is wrong.",
    agent: "shohei",
    url: "https://studio.example/content/dialogues/train-station/buying-a-ticket",
    noteCreatedAt: new Date("2026-10-06T18:00:00.000Z"),
    screenshotJpeg,
  };
}

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
    const payload = shoheiDeliveryPayload(job(null));
    assert.deepEqual(payload.metadata, {
      url: "https://studio.example/content/dialogues/train-station/buying-a-ticket",
      created_at: "2026-10-06T18:00:00.000Z",
    });
  });

  it("tells Shohei to write the JPEG to a file and read it", () => {
    const payload = shoheiDeliveryPayload(job(TINY_JPEG));
    assert.equal(payload.metadata.screenshot_jpeg, TINY_JPEG);
    assert.equal(payload.metadata.screenshot_jpeg_instructions, SCREENSHOT_JPEG_INSTRUCTIONS);
    assert.match(SCREENSHOT_JPEG_INSTRUCTIONS, /Write those bytes to a \.jpg file and read that image/);
  });
});

describe("shizenNoteSchema screenshot_jpeg", () => {
  it("accepts a note with no screenshot", () => {
    const parsed = shizenNoteSchema.safeParse(noteBody());
    assert.equal(parsed.success, true);
    if (parsed.success) assert.equal(parsed.data.metadata.screenshot_jpeg, undefined);
  });

  it("accepts a base64 JPEG and rejects other payloads", () => {
    const parsed = shizenNoteSchema.safeParse(noteBody(TINY_JPEG));
    assert.equal(parsed.success, true);

    const png = shizenNoteSchema.safeParse(noteBody("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="));
    assert.equal(png.success, false);
    if (!png.success) {
      assert.equal(noteValidationReason(png.error, noteBody("iVBORw0KGgo=")), "bad screenshot_jpeg");
    }
  });
});
