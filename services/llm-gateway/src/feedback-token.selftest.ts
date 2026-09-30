import assert from "node:assert/strict";

import { canonicalJSON } from "./canonical.js";
import {
  feedbackExpiry,
  signFeedbackToken,
  storesFeedbackPayload,
  verifyFeedbackToken,
  FEEDBACK_TOKEN_TTL_SECONDS,
} from "./feedback-token.js";

const secret = "test-secret-must-be-at-least-32-characters";
const input = { sentence: "おはよう", surface: "おはよう", dictionaryGloss: undefined };
const result = { meaning: "good morning", note: "" };
const exp = 1_800_000_000;
const parts = {
  uid: "user-1",
  exp,
  requestId: "11111111-1111-4111-8111-111111111111",
  feature: "span_gloss",
  model: "gemini-2.5-flash",
  input,
  result,
};

assert.equal(canonicalJSON({ b: 1, a: "x", c: undefined }), '{"a":"x","b":1}');
assert.equal(canonicalJSON([1, { z: true, a: null }]), '[1,{"a":null,"z":true}]');

const token = signFeedbackToken(secret, parts);
assert.equal(verifyFeedbackToken(secret, token, parts, exp - 10).ok, true);
assert.equal(verifyFeedbackToken(secret, token, { ...parts, uid: "other" }, exp - 10).ok, false);
assert.equal(verifyFeedbackToken(secret, token, { ...parts, result: { meaning: "nope", note: "" } }, exp - 10).ok, false);
assert.deepEqual(verifyFeedbackToken(secret, token, parts, exp + 1), { ok: false, reason: "expired" });

const mintedExp = feedbackExpiry(1_000);
assert.equal(mintedExp - 1_000, FEEDBACK_TOKEN_TTL_SECONDS);

let stored = 0;
for (let i = 0; i < 200; i++) {
  if (storesFeedbackPayload("up", `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`)) stored += 1;
}
assert.equal(storesFeedbackPayload("down", "any"), true);
assert.ok(stored > 5 && stored < 40, `expected about 1 in 10, got ${stored}/200`);

console.log("feedback-token selftest ok");
