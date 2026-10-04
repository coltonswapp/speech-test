/**
 * Run: pnpm exec tsx lib/usage/parse-feedback-doc.selftest.ts
 *
 * Examples mirror `services/llm-gateway/src/feedback.ts` vote payloads.
 */
import {
  parseFeedbackVoteDoc,
  serializeFirestoreTime,
} from "./parse-feedback-doc";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

assert(serializeFirestoreTime(null) === null, "null time");
assert(
  serializeFirestoreTime({ _seconds: 1_774_454_400, _nanoseconds: 0 }) ===
    "2026-03-25T16:00:00.000Z",
  "proto time",
);
assert(
  serializeFirestoreTime({
    toDate: () => new Date("2026-03-25T12:00:00.000Z"),
  }) === "2026-03-25T12:00:00.000Z",
  "toDate time",
);

const missing = parseFeedbackVoteDoc({
  id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  data: null,
});
assert(missing === null, "null data");

const noRating = parseFeedbackVoteDoc({
  id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  data: { feature: "span_gloss" },
});
assert(noRating === null, "missing rating");

const downWithPayload = parseFeedbackVoteDoc({
  id: "11111111-2222-3333-4444-555555555555",
  data: {
    rating: "down",
    reason: "wrong_meaning",
    feature: "span_gloss",
    model: "gemini-2.5-flash",
    requestId: "11111111-2222-3333-4444-555555555555",
    uid: "kYqKbEEc5FUmN2vLEWL3x9NRSVe2",
    createdAt: { _seconds: 1_774_454_400, _nanoseconds: 0 },
    expiresAt: { _seconds: 1_782_230_400, _nanoseconds: 0 },
    input: { surface: "は", sentence: "彼は学生です。" },
    result: { meaning: "topic marker", note: "not 'wa' as in…" },
  },
});
assert(downWithPayload, "down parses");
assert(downWithPayload!.hasPayload, "down has payload");
assert(downWithPayload!.reason === "wrong_meaning", "reason");
assert(
  downWithPayload!.input &&
    typeof downWithPayload!.input === "object" &&
    (downWithPayload!.input as { surface: string }).surface === "は",
  "input surface",
);
assert(
  downWithPayload!.createdAt === "2026-03-25T16:00:00.000Z",
  "createdAt iso",
);

const upNoPayload = parseFeedbackVoteDoc({
  id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  data: {
    rating: "up",
    feature: "span_gloss",
    model: "gemini-2.5-flash",
    requestId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    uid: "uid1",
    createdAt: { _seconds: 1_774_454_400, _nanoseconds: 0 },
    expiresAt: { _seconds: 1_782_230_400, _nanoseconds: 0 },
  },
});
assert(upNoPayload, "up parses");
assert(!upNoPayload!.hasPayload, "up without payload");
assert(upNoPayload!.input === null && upNoPayload!.result === null, "no fake gloss");
assert(upNoPayload!.reason === null, "no reason on up");

const upWithPayload = parseFeedbackVoteDoc({
  id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee",
  data: {
    rating: "up",
    feature: "nuance",
    model: "gemini-2.5-flash",
    requestId: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee",
    uid: "uid2",
    createdAt: { _seconds: 1_774_454_400, _nanoseconds: 0 },
    expiresAt: { _seconds: 1_782_230_400, _nanoseconds: 0 },
    input: { text: "ちょっと" },
    result: { gloss: "a bit / excuse me" },
  },
});
assert(upWithPayload!.hasPayload, "sampled up has payload");
assert(upWithPayload!.result != null, "sampled up result");

const unknownReason = parseFeedbackVoteDoc({
  id: "cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee",
  data: {
    rating: "down",
    reason: "not_a_real_reason",
    feature: "span_gloss",
    model: "m",
    requestId: "cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee",
    uid: "u",
    createdAt: { _seconds: 1, _nanoseconds: 0 },
    expiresAt: { _seconds: 2, _nanoseconds: 0 },
    input: {},
    result: {},
  },
});
assert(unknownReason!.reason === null, "unknown reason ignored");

console.log("parse-feedback-doc.selftest: ok");
