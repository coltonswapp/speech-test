import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  clipErrorResponse,
  clipUploadTokenMatches,
  createClipDraft,
  pcmWavInfo,
} from "@/lib/experiments/clips/route-helpers";
import { splitAtPauses, splitClipId } from "@/lib/experiments/clips/split";
import {
  clipExists,
  clipUploadAudioUrl,
  deleteClipUploadAudio,
  readClipPending,
  readClipUploadAudio,
  writeClipAudio,
  writeClipPending,
} from "@/lib/experiments/clips/store";
import { fetchYouTubeVideoInfo } from "@/lib/experiments/clips/youtube-info";
import {
  CLIP_MAX_SECONDS,
  CLIP_SAMPLE_RATE,
  CLIP_SPLIT_DEFAULT_TARGET_SECONDS,
  CLIP_SPLIT_MAX_SECONDS,
  CLIP_UPLOAD_MAX_SECONDS,
  type ClipPending,
  type ClipUploadTicket,
} from "@/lib/experiments/clips/types";
import { pcm16ToFloat32, pcm16ToWav } from "@/lib/tts/wav";

// Called by the clip audio script (public/clip-fetch.mjs), not a browser, so it
// sits under /hooks/ and skips the Studio proxy. Auth is the one-time token
// Studio issued with the pending clip (POST /api/experiments/clip-uploads),
// sent as a bearer and checked before anything else is done.

// A two-hour video is a couple of hundred clips to cut and store.
export const maxDuration = 300;

/** How far the uploaded audio may be from the range entered in Studio. */
const DURATION_TOLERANCE_SECONDS = 1;
const BYTES_PER_SECOND = CLIP_SAMPLE_RATE * 2;
const round3 = (n: number) => Math.round(n * 1000) / 1000;

/** The pending clip, or the 401 to send. One answer for every failure, so ids can't be probed. */
async function authorize(
  request: NextRequest,
  id: string
): Promise<{ pending: ClipPending } | { response: NextResponse }> {
  const pending = await readClipPending(id);
  const ok =
    pending !== null &&
    !pending.done &&
    clipUploadTokenMatches(request.headers.get("authorization"), pending.tokenHash) &&
    Date.parse(pending.expiresAt) > Date.now();
  if (!ok) {
    return {
      response: NextResponse.json(
        {
          error:
            "This upload command is no longer valid (used, replaced or expired). Get a new one in Studio.",
        },
        { status: 401 }
      ),
    };
  }
  return { pending };
}

/** The clip's details and a fresh signed upload URL for its WAV. */
export async function GET(request: NextRequest, ctx: RouteContext<"/hooks/clip-upload/[id]">) {
  try {
    const { id } = await ctx.params;
    const auth = await authorize(request, id);
    if ("response" in auth) return auth.response;
    const { pending } = auth;
    const ticket: ClipUploadTicket = {
      id: pending.id,
      videoId: pending.videoId,
      startSec: pending.startSec,
      endSec: pending.endSec,
      maxSeconds: CLIP_UPLOAD_MAX_SECONDS,
      sampleRate: CLIP_SAMPLE_RATE,
      uploadUrl: await clipUploadAudioUrl(pending.id),
    };
    return NextResponse.json(ticket, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return clipErrorResponse(error);
  }
}

/**
 * Finalize: checks the uploaded WAV against the pending clip's details and
 * makes the clip. Audio that fits one clip becomes clip `<id>`; longer audio,
 * or any audio when a split was asked for, is cut at pauses into `<id>-01`,
 * `<id>-02`, … exactly as Studio's file upload does it in the browser. Then
 * the token is retired.
 */
export async function POST(request: NextRequest, ctx: RouteContext<"/hooks/clip-upload/[id]">) {
  try {
    const { id } = await ctx.params;
    const auth = await authorize(request, id);
    if ("response" in auth) return auth.response;
    const { pending } = auth;

    const wav = await readClipUploadAudio(id);
    if (!wav) {
      return NextResponse.json({ error: "No audio has been uploaded yet." }, { status: 400 });
    }
    const info = pcmWavInfo(wav);
    if (!info || info.sampleRate !== CLIP_SAMPLE_RATE || info.channels !== 1) {
      return NextResponse.json(
        { error: `Clip audio must be a mono ${CLIP_SAMPLE_RATE} Hz 16-bit PCM WAV.` },
        { status: 400 }
      );
    }
    // Whole samples only, so every cut below lands on a sample.
    const pcm = wav.subarray(44, 44 + Math.floor((wav.length - 44) / 2) * 2);
    const totalSec = Math.floor((pcm.length / BYTES_PER_SECOND) * 1000) / 1000;
    if (totalSec < 0.2) {
      return NextResponse.json({ error: "Clip audio is empty." }, { status: 400 });
    }
    if (totalSec > CLIP_UPLOAD_MAX_SECONDS + 1) {
      return NextResponse.json(
        { error: `Audio is too long; the limit is ${CLIP_UPLOAD_MAX_SECONDS / 3600} hours.` },
        { status: 413 }
      );
    }
    const expected = pending.endSec === null ? null : pending.endSec - pending.startSec;
    if (expected !== null && Math.abs(totalSec - expected) > DURATION_TOLERANCE_SECONDS) {
      return NextResponse.json(
        {
          error: `Audio is ${totalSec.toFixed(1)} s but the range is ${expected.toFixed(1)} s. Is the end time past the end of the video?`,
        },
        { status: 422 }
      );
    }

    // One clip when it fits and no split was asked for; otherwise cut at pauses.
    const targetSec = pending.splitTargetSec ?? null;
    const single = targetSec === null && totalSec <= CLIP_MAX_SECONDS;
    const segments = single
      ? [{ startSec: 0, endSec: totalSec }]
      : splitAtPauses(
          pcm16ToFloat32(pcm),
          CLIP_SAMPLE_RATE,
          targetSec ?? CLIP_SPLIT_DEFAULT_TARGET_SECONDS,
          CLIP_SPLIT_MAX_SECONDS
        );
    const ids = single ? [id] : segments.map((_, i) => splitClipId(id, i, segments.length));

    // Check every id up front so a clash can't leave half a video made.
    const taken = await Promise.all(ids.map((candidate) => clipExists(candidate)));
    const clash = ids.find((_, i) => taken[i]);
    if (clash) {
      return NextResponse.json(
        {
          error: `Clip “${clash}” already exists. In Studio, discard this one and save it again with another id.`,
        },
        { status: 409 }
      );
    }

    // Looked up once for the whole run; null = YouTube didn't answer (Refresh fills it in later).
    const video = await fetchYouTubeVideoInfo(pending.videoId).catch(() => null);
    for (const [i, segment] of segments.entries()) {
      const from = Math.round(segment.startSec * CLIP_SAMPLE_RATE) * 2;
      const to = Math.min(pcm.length, Math.round(segment.endSec * CLIP_SAMPLE_RATE) * 2);
      const piece = pcm.subarray(from, to);
      try {
        await writeClipAudio(ids[i], pcm16ToWav(piece, CLIP_SAMPLE_RATE));
        await createClipDraft({
          id: ids[i],
          videoId: pending.videoId,
          startSec: round3(pending.startSec + segment.startSec),
          endSec:
            single && pending.endSec !== null
              ? pending.endSec
              : round3(pending.startSec + segment.endSec),
          orientation: pending.orientation,
          durationSec: piece.length / BYTES_PER_SECOND,
          video,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(
          i === 0 ? message : `Created ${i} of ${segments.length} clips, then failed: ${message}`
        );
      }
    }

    // Kept (without its audio) so an open Studio page can see what was made.
    await writeClipPending({ ...pending, done: { ids, at: new Date().toISOString() } });
    await deleteClipUploadAudio(id).catch(() => undefined);
    return NextResponse.json({ ids, videoId: pending.videoId }, { status: 201 });
  } catch (error) {
    return clipErrorResponse(error);
  }
}
