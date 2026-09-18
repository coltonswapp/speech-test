import type { TokenSyncFlag } from "@/lib/dialogue/types";
import { formatApiError } from "@/lib/api-error";
import type { VariantTokenSync } from "@/lib/dialogue/types";

export type ProjectSummary = {
  id: string;
  displayName: string;
  provider: string;
  voice: string;
  compositionMode: string;
  variantCount: number;
  groupId: string | null;
  groupTitle: string | null;
  groupOrderIndex: number | null;
  updatedAt: string;
  hasSelectedTake: boolean;
};

export type DialogueLine = {
  id: string;
  projectId: string;
  speaker: "speaker1" | "speaker2";
  text: string;
  orderIndex: number;
};

export type Project = {
  id: string;
  createdAt: string;
  updatedAt: string;
  promptText: string;
  instructions: string | null;
  provider: string;
  voice: string;
  model: string;
  selectedVariantId: string | null;
  compositionMode: string;
  speaker1Voice: string | null;
  speaker2Voice: string | null;
  speaker1Name: string | null;
  speaker2Name: string | null;
  trackName: string | null;
  groupId: string | null;
  sourceScenarioId: string | null;
  groupOrderIndex: number | null;
};

export type Variant = {
  id: string;
  projectId: string;
  createdAt: string;
  audioObjectKey: string;
  sampleRate: number;
  audioByteCount: number;
  trimSampleLower: number | null;
  trimSampleUpper: number | null;
  dialogueLineSwitchSamples: number[] | null;
  notes: string | null;
  rating: number | null;
  isSelected: boolean;
  voice: string;
  provider: string;
  contentHash: string | null;
  tokenSync: VariantTokenSync | null;
  /** Background generate → tokenize → align chain state; null when idle. */
  autoStampJob?: AutoStampJob | null;
};

export type AutoStampJob = {
  status: "queued" | "running" | "done" | "error" | "cancelled";
  message?: string;
  /** ISO time when the job was first queued (stable for elapsed duration). */
  startedAt: string;
  updatedAt: string;
  finishedAt?: string;
};

export function autoStampInProgress(variant: Pick<Variant, "autoStampJob">): boolean {
  const status = variant.autoStampJob?.status;
  return status === "queued" || status === "running";
}

/** Elapsed ms for a job: startedAt → finishedAt (or now while in flight). */
export function autoStampElapsedMs(
  job: Pick<AutoStampJob, "startedAt" | "finishedAt">,
  nowMs = Date.now()
): number {
  const start = new Date(job.startedAt).getTime();
  const end = job.finishedAt ? new Date(job.finishedAt).getTime() : nowMs;
  return Math.max(0, end - start);
}

/** Live label while running (`3.2s…`) or final (`took 8.2s`). */
export function formatAutoStampDuration(ms: number, opts?: { live?: boolean }): string {
  const seconds = ms / 1000;
  const body = seconds < 10 ? `${seconds.toFixed(1)}s` : `${Math.round(seconds)}s`;
  return opts?.live ? `${body}…` : `took ${body}`;
}

export type ReviewQueueResult = {
  takes: Array<{
    variantId: string;
    projectId: string;
    createdAt: string;
    voice: string;
    sampleRate: number;
    audioByteCount: number;
    dialogueLineSwitchSamples: number[] | null;
    scenarioId: string | null;
    collectionId: string | null;
    slug: string | null;
    title: string;
    isPublishedTake: boolean;
    isSelectedTake: boolean;
    flagCount: number;
    flagsByCode: Partial<Record<TokenSyncFlag["code"], number>>;
    flaggedLines: Array<{
      lineIndex: number;
      text: string;
      /** Seconds to seek when playing this flagged line (first stamped/flagged token). */
      playFromSeconds: number | null;
      /** Approximate end of the line for short segment playback. */
      playUntilSeconds: number | null;
      tokens: Array<{
        text: string;
        codes: TokenSyncFlag["code"][];
        startSeconds: number | null;
      }>;
      lineCodes: TokenSyncFlag["code"][];
    }>;
    /** All spoken lines with stamps — used for Play take karaoke follow. */
    lines: Array<{
      lineIndex: number;
      text: string;
      tokens: Array<{
        text: string;
        codes: TokenSyncFlag["code"][];
        startSeconds: number | null;
      }>;
    }>;
    lineCount: number;
    tokenCount: number;
    timing: {
      autoStampedAt?: string;
      openedAt?: string;
      reviewedAt?: string;
      publishedAt?: string;
      linesTouched?: number;
      maxCorrectionMs?: number;
    } | null;
  }>;
  timing: {
    bySource: Array<{
      source: "auto" | "human";
      published: number;
      medianOpenToPublishMinutes: number | null;
      withOpenTiming: number;
      linesUntouchedPct: number | null;
      correctionsOver200msPct: number | null;
    }>;
    since: string | null;
  };
};

export type AutoStampResult = {
  variant: Variant;
  flags: TokenSyncFlag[];
  marksDerived: boolean;
  summary: string;
};

export type SuggestBreaksResult = {
  suggestedSamples: number[];
  summary: string;
};

export type VoicePreview = {
  id: string;
  provider: string;
  voice: string;
  audioObjectKey: string;
  sampleRate: number;
};

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    ...init,
    headers: { "Content-Type": "application/json", ...init?.headers },
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(formatApiError(body, res.status));
  }
  return res.json();
}

export const ttsApi = {
  listProjects: () =>
    request<{ projects: ProjectSummary[] }>("/api/tts/projects"),
  getProject: (id: string) =>
    request<{ project: Project; dialogueLines: DialogueLine[] }>(
      `/api/tts/projects/${id}`
    ),
  createProject: (body: {
    promptText?: string;
    provider?: string;
    voice: string;
    model: string;
    compositionMode?: string;
    trackName?: string | null;
  }) =>
    request<{ project: Project }>("/api/tts/projects", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  updateProject: (id: string, body: Record<string, unknown>) =>
    request<{ project: Project }>(`/api/tts/projects/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  duplicateProject: (id: string) =>
    request<{ project: Project }>(`/api/tts/projects/${id}/duplicate`, {
      method: "POST",
    }),
  deleteProject: (id: string) =>
    request<{ ok: true }>(`/api/tts/projects/${id}`, { method: "DELETE" }),
  listVariants: (projectId: string) =>
    request<{ variants: Variant[] }>(
      `/api/tts/projects/${projectId}/variants`
    ),
  generate: (
    projectId: string,
    overrides?: {
      voice?: string;
      provider?: string;
      speaker1Voice?: string;
      speaker2Voice?: string;
    }
  ) =>
    request<{ variant: Variant }>(
      `/api/tts/projects/${projectId}/variants`,
      { method: "POST", body: overrides ? JSON.stringify(overrides) : undefined }
    ),
  deleteVariant: (projectId: string, variantId: string) =>
    request<{ ok: true }>(
      `/api/tts/projects/${projectId}/variants/${variantId}`,
      { method: "DELETE" }
    ),
  updateVariant: (projectId: string, variantId: string, body: Record<string, unknown>) =>
    request<{ variant: Variant }>(
      `/api/tts/projects/${projectId}/variants/${variantId}`,
      {
        method: "PATCH",
        body: JSON.stringify(body),
      }
    ),
  selectVariant: (projectId: string, variantId: string) =>
    request<{ ok: true }>(
      `/api/tts/projects/${projectId}/variants/${variantId}/select`,
      { method: "POST" }
    ),
  acceptScript: (projectId: string, variantId: string, contentHash?: string) =>
    request<{ variant: Variant }>(
      `/api/tts/projects/${projectId}/variants/${variantId}/accept-script`,
      {
        method: "POST",
        body: JSON.stringify(contentHash ? { contentHash } : {}),
      }
    ),
  reviewEvent: (projectId: string, variantId: string, event: "opened" | "reviewed") =>
    request<{ ok: true }>(
      `/api/tts/projects/${projectId}/variants/${variantId}/review-event`,
      { method: "POST", body: JSON.stringify({ event }) }
    ),
  markReviewed: (projectId: string, variantId: string) =>
    request<{ variant: Variant; alreadyReviewed: boolean }>(
      `/api/tts/projects/${projectId}/variants/${variantId}/mark-reviewed`,
      { method: "POST" }
    ),
  reviewQueue: () => request<ReviewQueueResult>("/api/tts/review-queue"),
  autoStamp: (projectId: string, variantId: string, body?: { force?: boolean }) =>
    request<AutoStampResult>(
      `/api/tts/projects/${projectId}/variants/${variantId}/auto-stamp`,
      { method: "POST", body: JSON.stringify(body ?? {}) }
    ),
  cancelAutoStamp: (projectId: string, variantId: string) =>
    request<{ ok: true; job: AutoStampJob }>(
      `/api/tts/projects/${projectId}/variants/${variantId}/auto-stamp`,
      { method: "DELETE" }
    ),
  suggestBreaks: (projectId: string, variantId: string) =>
    request<SuggestBreaksResult>(
      `/api/tts/projects/${projectId}/variants/${variantId}/suggest-breaks`,
      { method: "POST" }
    ),
  insertLineBreak: (
    projectId: string,
    variantId: string,
    sample: number,
    durationSeconds?: number
  ) =>
    request<{ variant: Variant }>(
      `/api/tts/projects/${projectId}/variants/${variantId}/insert-line-break`,
      {
        method: "POST",
        body: JSON.stringify({ sample, durationSeconds }),
      }
    ),
  listVoicePreviews: () =>
    request<{ previews: VoicePreview[] }>("/api/tts/voice-previews"),
  /** Studio audio proxy URL for a take (same path the waveform editor uses). */
  variantAudioUrl: (projectId: string, variantId: string, audioByteCount?: number) =>
    `/api/tts/projects/${projectId}/variants/${variantId}/audio${
      audioByteCount != null ? `?v=${audioByteCount}` : ""
    }`,
};