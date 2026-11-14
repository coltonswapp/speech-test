import { formatApiError } from "@/lib/api-error";
import type { VariantTokenSync } from "@/lib/dialogue/types";
import type {
  GenerateLineInput,
  GenerateLineTiming,
  GenerateKind,
  GenerationStatus,
} from "./types";
import { GENERATE_TEMPORARY_LIFETIME } from "./types";

export type Generation = {
  id: string;
  createdAt: string;
  updatedAt: string;
  savedAt: string | null;
  expiresAt: string | null;
  status: GenerationStatus;
  title: string;
  kind: GenerateKind;
  model: string | null;
  requestId: string | null;
  contentHash: string | null;
  lines: GenerateLineInput[];
  lineTimings: GenerateLineTiming[] | null;
  tokenSync: VariantTokenSync | null;
  transcript: string | null;
  sampleRate: number | null;
  durationSeconds: number;
  byteCount: number | null;
  saved: boolean;
  temporary: boolean;
  audioUrl: string;
  downloadUrl: string;
  timingUrl: string | null;
};

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const headers = new Headers(init?.headers);
  if (init?.body && !(init.body instanceof FormData) && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  const res = await fetch(url, { ...init, headers });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(formatApiError(body, res.status));
  }
  return res.json();
}

export const generateApi = {
  temporaryLifetime: GENERATE_TEMPORARY_LIFETIME,
  list: () =>
    request<{ generations: Generation[]; temporaryLifetime: string }>(
      "/api/generate",
    ),
  create: (body: {
    title?: string;
    lines: GenerateLineInput[];
    requestId: string;
  }) =>
    request<{ generation: Generation; reused: boolean; model: string }>(
      "/api/generate",
      { method: "POST", body: JSON.stringify(body) },
    ),
  get: (id: string) =>
    request<{ generation: Generation }>(`/api/generate/${id}`),
  patch: (id: string, body: { title?: string; saved?: boolean }) =>
    request<{ generation: Generation }>(`/api/generate/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  remove: (id: string) =>
    request<{ ok: true }>(`/api/generate/${id}`, { method: "DELETE" }),
  align: (id: string, transcript?: string) =>
    request<{ generation: Generation }>(`/api/generate/${id}/align`, {
      method: "POST",
      body: JSON.stringify({ transcript }),
    }),
  upload: (params: {
    file: File;
    transcript: string;
    title?: string;
    requestId: string;
  }) => {
    const form = new FormData();
    form.set("file", params.file);
    form.set("transcript", params.transcript);
    if (params.title) form.set("title", params.title);
    form.set("requestId", params.requestId);
    return request<{ generation: Generation }>("/api/generate/upload", {
      method: "POST",
      body: form,
    });
  },
};
