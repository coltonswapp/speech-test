import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { describe, it } from "node:test";
import { grokBotHeaders, openBotEnvelope, openBotSignatureHeaders } from "./signing";

describe("openBotSignatureHeaders", () => {
  it("signs timestamp.id.body with the trimmed secret, hex, in whole seconds", () => {
    const body = openBotEnvelope("clip-feedback.attempt", "2026-11-20T00:00:00.000Z", { a: 1 });
    const headers = openBotSignatureHeaders(" s3cret\n", "att_x", body, new Date(1_763_600_000_900));
    assert.equal(headers["X-OpenBot-Timestamp"], "1763600000");
    assert.equal(headers["X-OpenBot-Delivery-Id"], "att_x");
    const expected = createHmac("sha256", "s3cret").update(`1763600000.att_x.${body}`).digest("hex");
    assert.equal(headers["X-OpenBot-Signature"], `sha256=${expected}`);
  });

  it("wraps data in the {type, occurredAt, data} envelope", () => {
    assert.deepEqual(JSON.parse(openBotEnvelope("t", "2026-11-20T00:00:00.000Z", { b: 2 })), {
      type: "t",
      occurredAt: "2026-11-20T00:00:00.000Z",
      data: { b: 2 },
    });
  });
});

describe("grokBotHeaders", () => {
  it("sends the key as bearer and automation key", () => {
    assert.deepEqual(grokBotHeaders("k"), { Authorization: "Bearer k", "X-Automation-Key": "k" });
  });
});
