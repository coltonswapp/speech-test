/** Private R2 prefix for one-off Generate clips. Never overlaps takes or published audio. */
export const GENERATE_R2_PREFIX = "tts/generate/";

export function generateWavKey(id: string): string {
  return `${GENERATE_R2_PREFIX}${id}/audio.wav`;
}

export function generateMp3Key(id: string): string {
  return `${GENERATE_R2_PREFIX}${id}/audio.mp3`;
}

export function generateSourceKey(id: string, ext: string): string {
  return `${GENERATE_R2_PREFIX}${id}/source.${ext}`;
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
