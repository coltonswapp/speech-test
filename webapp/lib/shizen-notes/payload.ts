/**
 * Shohei receives the webhook as text. This sentence sits next to the bytes so
 * the routine writes a file and reads the image instead of staring at base64.
 */
export const SCREENSHOT_JPEG_INSTRUCTIONS =
  "screenshot_jpeg is a base64-encoded JPEG with no data: prefix. It is a snapshot of the lesson view under the QA note sheet. Write those bytes to a .jpg file and read that image before acting on the note. The base64 text is not the picture.";

export type ShoheiNoteJob = {
  id: string;
  source: string;
  sourceId: string;
  title: string | null;
  note: string;
  agent: string;
  url: string;
  noteCreatedAt: Date;
  screenshotJpeg: string | null;
};

/** JSON body posted to SHOHEI_DELIVERY_URL. */
export function shoheiDeliveryPayload(job: ShoheiNoteJob) {
  return {
    job_id: job.id,
    source: job.source,
    source_id: job.sourceId,
    ...(job.title ? { title: job.title } : {}),
    note: job.note,
    agent: job.agent,
    metadata: {
      url: job.url,
      created_at: job.noteCreatedAt.toISOString(),
      ...(job.screenshotJpeg
        ? {
            screenshot_jpeg: job.screenshotJpeg,
            screenshot_jpeg_instructions: SCREENSHOT_JPEG_INSTRUCTIONS,
          }
        : {}),
    },
  };
}
