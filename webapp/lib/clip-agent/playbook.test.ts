import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { clipFeedbackPlaybook } from "./playbook";

describe("clipFeedbackPlaybook", () => {
  it("tells agents to swap a single misheard word instead of rewriting sentences", () => {
    const reading = clipFeedbackPlaybook("reading");
    assert.match(reading, /patch_clip swap \{sentence, token, text, reading\}/);
    assert.match(reading, /keeps timings and the feed verdict/);

    const transcription = clipFeedbackPlaybook("transcription");
    assert.match(transcription, /Bad transcription/);
    assert.match(transcription, /patch_clip swap \{sentence, token, text, reading\?, english\?\}/);

    const rules = clipFeedbackPlaybook("other");
    assert.match(rules, /Don't send sentences for a one-word fix/);
    assert.match(rules, /patch_clip swap \{sentence, token, text, reading\?, english\?\}/);
  });
});
