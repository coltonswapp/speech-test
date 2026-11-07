/** Private R2 prefix for one-off Generate clips. Never overlaps takes or published audio. */
export const GENERATE_R2_PREFIX = "tts/generate/";

function attemptSegment(attempt: number): string {
  if (!Number.isInteger(attempt) || attempt < 0) {
    throw new Error("Generate object attempt must be a non-negative integer.");
  }
  return String(attempt);
}

/** Playable files are scoped to a reservation attempt so a delayed fail-cleanup cannot delete a retry. */
export function generateWavKey(id: string, attempt: number): string {
  return `${GENERATE_R2_PREFIX}${id}/${attemptSegment(attempt)}/audio.wav`;
}

export function generateMp3Key(id: string, attempt: number): string {
  return `${GENERATE_R2_PREFIX}${id}/${attemptSegment(attempt)}/audio.mp3`;
}

export function generateSourceKey(id: string, attempt: number, ext: string): string {
  return `${GENERATE_R2_PREFIX}${id}/${attemptSegment(attempt)}/source.${ext}`;
}

export function assertGenerateObjectKey(key: string): void {
  if (!key.startsWith(GENERATE_R2_PREFIX) || key.includes("..") || key.includes("//")) {
    throw new Error("Refusing to touch a non-Generate object.");
  }
}

export function isGenerateObjectKey(key: string): boolean {
  return (
    key.startsWith(GENERATE_R2_PREFIX) &&
    !key.includes("..") &&
    !key.includes("//")
  );
}
