import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { resolveShoheiDeliveryTarget } from "./delivery-target";

describe("resolveShoheiDeliveryTarget", () => {
  it("returns bearer Authorization when URL and key are set", () => {
    const target = resolveShoheiDeliveryTarget({
      SHOHEI_DELIVERY_URL: " https://shohei.example/hook ",
      SHOHEI_WEBHOOK_KEY: " test-key ",
    });

    assert.deepEqual(target, {
      ok: true,
      url: "https://shohei.example/hook",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer test-key",
      },
    });
  });

  it("errors without posting when delivery URL is missing", () => {
    const target = resolveShoheiDeliveryTarget({
      SHOHEI_WEBHOOK_KEY: "test-key",
    });

    assert.deepEqual(target, {
      ok: false,
      error: "SHOHEI_DELIVERY_URL is not set",
    });
  });

  it("errors without posting when webhook key is missing", () => {
    const target = resolveShoheiDeliveryTarget({
      SHOHEI_DELIVERY_URL: "https://shohei.example/hook",
    });

    assert.deepEqual(target, {
      ok: false,
      error: "SHOHEI_WEBHOOK_KEY is not set",
    });
  });

  it("treats blank webhook key as missing", () => {
    const target = resolveShoheiDeliveryTarget({
      SHOHEI_DELIVERY_URL: "https://shohei.example/hook",
      SHOHEI_WEBHOOK_KEY: "   ",
    });

    assert.deepEqual(target, {
      ok: false,
      error: "SHOHEI_WEBHOOK_KEY is not set",
    });
  });
});
