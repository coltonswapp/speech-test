import { formatApiError } from "@/lib/api-error";
import type { ClipTagPick } from "@/lib/experiments/clips/tags";
import type { DialogueHighlights } from "@/lib/dialogue/types";
import type {
  ClipDraft,
  ClipDraftResponse,
  ClipOrientation,
  ClipPendingInfo,
  ClipSummary,
} from "@/lib/experiments/clips/types";

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, init);
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new Error(formatApiError(body, response.status));
  }
  return response.json() as Promise<T>;
}

const json = (body: unknown): RequestInit => ({
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(body),
});

export const clipsApi = {
  /** `pending`: clips waiting for the clip audio script to upload their audio. */
  list: () =>
    request<{ clips: ClipSummary[]; pending?: ClipPendingInfo[] }>("/api/experiments/clips"),
  /**
   * Saves a clip's details and returns the one-time token for the script
   * command. Calling it again for a pending id replaces the old command.
   */
  createUpload: (input: {
    id: string;
    videoId: string;
    startSec: number;
    /** null = to the end of the video. */
    endSec: number | null;
    orientation: ClipOrientation;
    /** Split at pauses into clips of about this length; null = only if too long for one clip. */
    splitTargetSec: number | null;
  }) =>
    request<{ pending: ClipPendingInfo; token: string }>("/api/experiments/clip-uploads", {
      method: "POST",
      ...json(input),
    }),
  /** `created`: the ids of the clips made, once the script has uploaded; null until then. */
  uploadStatus: (id: string) =>
    request<{ pending: ClipPendingInfo | null; created: string[] | null; videoId: string | null }>(
      `/api/experiments/clip-uploads/${id}`
    ),
  cancelUpload: (id: string) =>
    request<{ ok: true }>(`/api/experiments/clip-uploads/${id}`, { method: "DELETE" }),
  get: (id: string) => request<ClipDraftResponse>(`/api/experiments/clips/${id}`),
  create: (input: {
    id: string;
    videoId: string;
    startSec: number;
    endSec: number;
    orientation: ClipOrientation;
    wav: Blob;
  }) => {
    const form = new FormData();
    form.set("orientation", input.orientation);
    form.set("id", input.id);
    form.set("videoId", input.videoId);
    form.set("startSec", String(input.startSec));
    form.set("endSec", String(input.endSec));
    form.set("file", input.wav, `${input.id}.wav`);
    return request<{ draft: ClipDraft }>("/api/experiments/clips", {
      method: "POST",
      body: form,
    });
  },
  patch: (
    id: string,
    body: {
      sentences?: string[];
      /** Break one line at token boundaries without dropping tokens or alignment. */
      split?: { sentence: number; atToken: number | number[]; english?: string[] };
      /** Join a line with the following `count` lines (default 1). */
      merge?: { sentence: number; count?: number; english?: string };
      shiftSec?: number;
      orientation?: ClipOrientation;
      english?: string[];
      highlights?: DialogueHighlights | null;
      tokens?: {
        sentence: number;
        tokens: { text: string; reading?: string }[];
        text?: string;
        english?: string;
      };
      /** One-token surface/reading swap; keeps timings and the feed verdict. */
      swap?: { sentence: number; token: number; text: string; reading?: string; english?: string };
      clearFlags?: { sentence: number; cleared: boolean };
      /** 5 = N5 … 1 = N1; null clears the rating. */
      jlptLevel?: number | null;
      /** Hand-set feed answer; null = back to the automatic verdict. */
      feedEligible?: boolean | null;
      /** Hand-set catalog tags; null = back to the Tag step's. */
      tags?: ClipTagPick | null;
      /** Retire the clip, or null to restore it. */
      deprecated?: { reason?: string } | null;
    }
  ) =>
    request<{ draft: ClipDraft }>(`/api/experiments/clips/${id}`, {
      method: "PATCH",
      ...json(body),
    }),
  delete: (id: string) =>
    request<{ ok: true }>(`/api/experiments/clips/${id}`, { method: "DELETE" }),
  /** `model` applies to transcribe, translate, level, tag and feed; omitted = server default. */
  step: (
    id: string,
    step: "transcribe" | "translate" | "tokenize" | "align" | "level" | "tag" | "feed",
    model?: string
  ) =>
    request<{ draft: ClipDraft }>(`/api/experiments/clips/${id}/${step}`, {
      method: "POST",
      ...(model ? json({ model }) : {}),
    }),
  /** Fetch or refresh the video's title and channel from YouTube. */
  videoInfo: (id: string) =>
    request<{ draft: ClipDraft }>(`/api/experiments/clips/${id}/video-info`, { method: "POST" }),
  /** Align only lines without timings; timed lines are left untouched. */
  alignUntimed: (id: string) =>
    request<{ draft: ClipDraft }>(`/api/experiments/clips/${id}/align`, {
      method: "POST",
      ...json({ onlyUntimed: true }),
    }),
};
