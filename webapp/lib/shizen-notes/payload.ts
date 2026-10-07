/** Signed R2 links stay valid this long. SigV4 presigning caps at 7 days. */
export const SCREENSHOT_URL_TTL_SECONDS = 3 * 24 * 60 * 60;

/**
 * Shohei's webhook ingest may strip large fields, so the image travels as a
 * short signed link. Fetching a URL is not the same as seeing the image; the
 * routine has to download to a file and read that file.
 */
export const SCREENSHOT_URL_INSTRUCTIONS =
  "screenshot_url is a signed link to a JPEG of the lesson view under the QA note sheet. It expires in about 3 days. Run `curl -fsSL -o screenshot.jpg \"<screenshot_url>\"`, then read screenshot.jpg as an image before acting on the note.";

export type ShoheiNoteJob = {
  id: string;
  source: string;
  sourceId: string;
  title: string | null;
  note: string;
  agent: string;
  url: string;
  noteCreatedAt: Date;
};

/** Object key for a note screenshot. The random suffix keeps keys unguessable. */
export function screenshotObjectKey(jobId: string, randomSuffix: string): string {
  return `shizen-notes/${jobId}-${randomSuffix}.jpg`;
}

/** JSON body posted to SHOHEI_DELIVERY_URL. */
export function shoheiDeliveryPayload(job: ShoheiNoteJob, screenshotUrl: string | null) {
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
      ...(screenshotUrl
        ? {
            screenshot_url: screenshotUrl,
            screenshot_instructions: SCREENSHOT_URL_INSTRUCTIONS,
          }
        : {}),
    },
  };
}
