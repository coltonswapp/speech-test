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
};
