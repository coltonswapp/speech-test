import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  clipErrorResponse,
  pcmWavInfo,
} from "@/lib/experiments/clips/route-helpers";
import {
  clipExists,
  isValidClipId,
  listClipSummaries,
  writeClipAudio,
  writeClipDraft,
} from "@/lib/experiments/clips/store";
import { fetchYouTubeVideoInfo } from "@/lib/experiments/clips/youtube-info";
import {
  CLIP_DEFAULT_SHIFT_SECONDS,
  CLIP_MAX_SECONDS,
  YOUTUBE_ID_PATTERN,
  clipOrientationSchema,
  type ClipDraft,
} from "@/lib/experiments/clips/types";

// The browser cuts the window and encodes mono 16 kHz WAV, so a 120 s clip is
// ~3.8 MB: under Vercel's request body limit.
const MAX_BYTES = 4_200_000;

export async function GET() {
  try {
    return NextResponse.json({ clips: await listClipSummaries() });
  } catch (error) {
    return clipErrorResponse(error);
  }
}

/**
 * Multipart: file (clip WAV), id, videoId, startSec, endSec, optional
 * orientation. Also looks up the video's title and channel on YouTube.
 */
export async function POST(request: NextRequest) {
  try {
    const declared = Number(request.headers.get("content-length") ?? 0);
    if (declared > MAX_BYTES + 10_000) {
      return NextResponse.json({ error: "Clip audio is too large." }, { status: 413 });
    }
    const form = await request.formData();
    const file = form.get("file");
    const id = String(form.get("id") ?? "").trim();
    const videoId = String(form.get("videoId") ?? "").trim();
    const startSec = Number(form.get("startSec"));
    const endSec = Number(form.get("endSec"));
    const orientation = clipOrientationSchema.safeParse(form.get("orientation") ?? "landscape");

    if (!isValidClipId(id)) {
      return NextResponse.json(
        { error: "Clip id must be lowercase letters, digits and dashes." },
        { status: 400 }
      );
    }
    if (!YOUTUBE_ID_PATTERN.test(videoId)) {
      return NextResponse.json({ error: "Invalid YouTube video id." }, { status: 400 });
    }
    if (!orientation.success) {
      return NextResponse.json(
        { error: "Orientation must be landscape or portrait." },
        { status: 400 }
      );
    }
    if (!Number.isFinite(startSec) || !Number.isFinite(endSec) || startSec < 0 || endSec <= startSec) {
      return NextResponse.json({ error: "End must be after start." }, { status: 400 });
    }
    if (endSec - startSec > CLIP_MAX_SECONDS) {
      return NextResponse.json(
        { error: `Clips are limited to ${CLIP_MAX_SECONDS} s.` },
        { status: 400 }
      );
    }
    if (!(file instanceof File) || file.size === 0 || file.size > MAX_BYTES) {
      return NextResponse.json({ error: "Expected the clip WAV in “file”." }, { status: 400 });
    }
    if (await clipExists(id)) {
      return NextResponse.json({ error: `Clip “${id}” already exists.` }, { status: 409 });
    }

    const wav = Buffer.from(await file.arrayBuffer());
    const info = pcmWavInfo(wav);
    if (!info) {
      return NextResponse.json({ error: "Clip audio is not a PCM WAV." }, { status: 400 });
    }

    // Best effort: a clip is still created if YouTube can't be reached; the
    // editor's Refresh (or "Process" on the list) fills it in later.
    const video = await fetchYouTubeVideoInfo(videoId).catch(() => undefined);
    const now = new Date().toISOString();
    const draft: ClipDraft = {
      id,
      videoId,
      ...(video ? { video } : {}),
      startSec,
      endSec,
      orientation: orientation.data,
      durationSec: Math.round(info.durationSec * 1000) / 1000,
      shiftSec: CLIP_DEFAULT_SHIFT_SECONDS,
      sentences: [],
      createdAt: now,
      updatedAt: now,
    };
    await writeClipAudio(id, wav);
    const saved = await writeClipDraft(draft);
    return NextResponse.json({ draft: saved }, { status: 201 });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
