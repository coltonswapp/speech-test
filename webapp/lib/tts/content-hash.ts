// Fingerprint of the spoken content of a take, stored on tts_variant at
// generation time and compared against the current scenario lines to detect
// stale audio. Hashes the mapped speaker slot (speaker1/speaker2), not the
// display name — Gemini's transcript uses "Speaker 1:/Speaker 2:" labels, so
// renaming a speaker doesn't change the audio.

import { createHash } from "node:crypto";

export function conversationContentHash(
  lines: { speaker: string; text: string }[]
): string {
  const payload = JSON.stringify(
    lines.map((line) => [line.speaker, line.text.trim()])
  );
  return createHash("sha256").update(payload, "utf8").digest("hex");
}
