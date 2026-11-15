import { randomBytes } from "node:crypto";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { clipErrorResponse, clipUploadTokenHash } from "@/lib/experiments/clips/route-helpers";
import { clipExists, discardClipPending, readClipPending, writeClipPending } from "@/lib/experiments/clips/store";
import {
  CLIP_ID_PATTERN,
  CLIP_PENDING_TTL_HOURS,
  CLIP_SPLIT_MAX_SECONDS,
  CLIP_SPLIT_MIN_TARGET_SECONDS,
  CLIP_UPLOAD_MAX_SECONDS,
  YOUTUBE_ID_PATTERN,
  clipOrientationSchema,
  clipPendingInfo,
  type ClipPending,
} from "@/lib/experiments/clips/types";

const bodySchema = z.object({
  /** The clip id, or the id prefix when the audio ends up split. */
  id: z.string().regex(CLIP_ID_PATTERN).max(60),
  videoId: z.string().regex(YOUTUBE_ID_PATTERN),
  startSec: z.number().min(0),
  /** null = to the end of the video. */
  endSec: z.number().positive().nullable(),
  orientation: clipOrientationSchema.default("landscape"),
  /** Split at pauses into clips of about this length; null/omitted = only if too long for one clip. */
  splitTargetSec: z
    .number()
    .min(CLIP_SPLIT_MIN_TARGET_SECONDS)
    .max(CLIP_SPLIT_MAX_SECONDS)
    .nullable()
    .optional(),
});

/**
 * Step one of a script-made clip: save the clip's details and hand back a
 * one-time token. The clip audio script (public/clip-fetch.mjs) then
 * downloads the audio with yt-dlp on the editor's machine, uploads it
 * straight to R2, and calls /hooks/clip-upload/[id] with the token, which
 * makes the clip (or splits long audio into a run of clips).
 *
 * Posting again for an id that is still pending replaces it (new details, new
 * token; the old command stops working).
 */
export async function POST(request: NextRequest) {
  try {
    const parsed = bodySchema.safeParse(await request.json().catch(() => null));
    if (!parsed.success) {
      return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
    }
    const { id, videoId, startSec, endSec, orientation, splitTargetSec } = parsed.data;
    if (endSec !== null && endSec <= startSec) {
      return NextResponse.json({ error: "End must be after start." }, { status: 400 });
    }
    if (endSec !== null && endSec - startSec > CLIP_UPLOAD_MAX_SECONDS) {
      return NextResponse.json(
        { error: `A range can be at most ${CLIP_UPLOAD_MAX_SECONDS / 3600} hours.` },
        { status: 400 }
      );
    }
    if (await clipExists(id)) {
      return NextResponse.json({ error: `Clip “${id}” already exists.` }, { status: 409 });
    }
    // Audio left by an earlier attempt must not be mistaken for this one's.
    if (await readClipPending(id)) await discardClipPending(id);

    const token = randomBytes(32).toString("hex");
    const now = Date.now();
    const pending: ClipPending = {
      id,
      videoId,
      startSec,
      endSec,
      orientation,
      splitTargetSec: splitTargetSec ?? null,
      tokenHash: clipUploadTokenHash(token),
      createdAt: new Date(now).toISOString(),
      expiresAt: new Date(now + CLIP_PENDING_TTL_HOURS * 3_600_000).toISOString(),
    };
    await writeClipPending(pending);
    return NextResponse.json({ pending: clipPendingInfo(pending), token }, { status: 201 });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
