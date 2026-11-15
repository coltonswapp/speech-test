import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  clipErrorResponse,
  createClipDraft,
  pcmWavInfo,
} from "@/lib/experiments/clips/route-helpers";
import {
  clipExists,
  discardClipPending,
  isValidClipId,
  listClipPendings,
  listClipSummaries,
  writeClipAudio,
} from "@/lib/experiments/clips/store";
import {
  CLIP_MAX_SECONDS,
  YOUTUBE_ID_PATTERN,
  clipOrientationSchema,
  clipPendingInfo,
  type ClipPendingInfo,
} from "@/lib/experiments/clips/types";

// The browser cuts the window and encodes mono 16 kHz WAV, so a 120 s clip is
// ~3.8 MB: under Vercel's request body limit.
const MAX_BYTES = 4_200_000;

export async function GET() {
  try {
    const [clips, pendings] = await Promise.all([listClipSummaries(), listClipPendings()]);
    // Clips waiting for the clip audio script to upload their audio. A
    // finished one lingers only so an open Studio page can see the result.
    const stale = pendings.filter(
      (p) => p.done && Date.now() - Date.parse(p.done.at) > 3_600_000
    );
    await Promise.all(stale.map((p) => discardClipPending(p.id).catch(() => undefined)));
    const pending: ClipPendingInfo[] = pendings.filter((p) => !p.done).map(clipPendingInfo);
    return NextResponse.json({ clips, pending });
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

    await writeClipAudio(id, wav);
    const saved = await createClipDraft({
      id,
      videoId,
      startSec,
      endSec,
      orientation: orientation.data,
      durationSec: info.durationSec,
    });
    // The id is taken now, so a script upload waiting on it can never finish.
    await discardClipPending(id).catch(() => undefined);
    return NextResponse.json({ draft: saved }, { status: 201 });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
