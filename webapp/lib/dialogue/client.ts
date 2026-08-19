import type {
  AuditScenarioResult,
  CollectionFile,
  DialogueHighlights,
  DialogueLine,
  ExtractedHighlights,
  GeneratedLines,
  GeneratedQuiz,
  GeneratedScenario,
  QuizQuestion,
  ReviseLinesResult,
  SanitizeGrammarResult,
} from "@/lib/dialogue/types";
import type { Project as TtsProject } from "@/lib/tts/client";
import { formatApiError } from "@/lib/api-error";

export type ScenarioAudio = {
  project: TtsProject | null;
  currentContentHash: string;
  speakerNames: string[];
};

export type ScenarioAudioStatus = {
  id: string;
  hasProject: boolean;
  hasSelectedTake: boolean;
  stale: boolean;
  published: boolean;
  publishStale: boolean;
};

export type ScenarioSummary = {
  id: string;
  collectionId: string;
  orderIndex: number;
  menuTitle: string;
  menuSubtitle: string | null;
  audioKey: string | null;
  publishedAudioUrl: string | null;
  publishedVariantId: string | null;
  publishedContentHash: string | null;
  publishedAt: string | null;
  updatedAt: string;
};

export type CollectionSummary = {
  id: string;
  unitId: string | null;
  title: string;
  subtitle: string | null;
  premise: string | null;
  sceneImage: string | null;
  thumbnailUrl: string | null;
  orderIndex: number;
  updatedAt: string;
  scenarios: ScenarioSummary[];
};

export type Unit = {
  id: string;
  title: string;
  subtitle: string | null;
  jlptLevel: number;
  orderIndex: number;
  updatedAt: string;
};

export type UnitSummary = Unit & {
  collections: Array<{ id: string; unitId: string | null; title: string }>;
};

export type DialogueScenario = {
  id: string;
  collectionId: string;
  orderIndex: number;
  menuTitle: string;
  menuSubtitle: string | null;
  japanese: string;
  romaji: string;
  english: string;
  targetSubstring: string | null;
  audioKey: string | null;
  publishedAudioUrl: string | null;
  publishedVariantId: string | null;
  publishedContentHash: string | null;
  publishedAt: string | null;
  grammarPointIds: string[];
  setting: string | null;
  lines: DialogueLine[];
  highlights: DialogueHighlights | null;
  quiz: QuizQuestion[] | null;
  updatedAt: string;
};

export type DialogueCollection = Omit<CollectionSummary, "scenarios"> & {
  scenarios: DialogueScenario[];
};

// Scenario ids are "<collectionId>/<slug>"; routes take the pieces separately.
export function scenarioSlug(scenario: { id: string; collectionId: string }) {
  return scenario.id.slice(scenario.collectionId.length + 1);
}

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

export const dialogueApi = {
  listCollections: () =>
    request<{ collections: CollectionSummary[] }>("/api/content/dialogues"),
  listUnits: () => request<{ units: UnitSummary[] }>("/api/content/units"),
  createUnit: (body: {
    id: string;
    title: string;
    subtitle?: string;
    jlptLevel?: number;
    orderIndex?: number;
  }) =>
    request<{ unit: Unit }>("/api/content/units", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  updateUnit: (
    unitId: string,
    body: {
      title?: string;
      subtitle?: string | null;
      jlptLevel?: number;
      orderIndex?: number;
      collectionOrder?: string[];
    },
  ) =>
    request<{ unit: Unit }>(`/api/content/units/${unitId}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  deleteUnit: (unitId: string) =>
    request<{ ok: true }>(`/api/content/units/${unitId}`, {
      method: "DELETE",
    }),
  createCollection: (body: {
    id: string;
    title: string;
    subtitle?: string;
    premise?: string;
    sceneImage?: string;
    unitId?: string;
  }) =>
    request<{ collection: DialogueCollection }>("/api/content/dialogues", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  getCollection: (collectionId: string) =>
    request<{ collection: DialogueCollection }>(
      `/api/content/dialogues/${collectionId}`,
    ),
  updateCollection: (
    collectionId: string,
    body: {
      title?: string;
      unitId?: string | null;
      subtitle?: string | null;
      premise?: string | null;
      sceneImage?: string | null;
      thumbnailUrl?: string | null;
      orderIndex?: number;
      scenarioOrder?: string[];
    },
  ) =>
    request<{ collection: DialogueCollection }>(
      `/api/content/dialogues/${collectionId}`,
      { method: "PATCH", body: JSON.stringify(body) },
    ),
  uploadThumbnail: async (collectionId: string, file: File) => {
    const formData = new FormData();
    formData.append("file", file);
    const res = await fetch(
      `/api/content/dialogues/${collectionId}/thumbnail`,
      { method: "POST", body: formData },
    );
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(
        typeof body?.error === "string"
          ? body.error
          : "Thumbnail upload failed",
      );
    }
    return res.json() as Promise<{
      collection: DialogueCollection;
      thumbnailUrl: string;
    }>;
  },
  clearThumbnail: (collectionId: string) =>
    request<{ collection: DialogueCollection }>(
      `/api/content/dialogues/${collectionId}/thumbnail`,
      { method: "DELETE" },
    ),
  replaceCollection: (collectionId: string, file: CollectionFile) =>
    request<{ collection: DialogueCollection }>(
      `/api/content/dialogues/${collectionId}`,
      { method: "PUT", body: JSON.stringify(file) },
    ),
  deleteCollection: (collectionId: string) =>
    request<{ ok: true }>(`/api/content/dialogues/${collectionId}`, {
      method: "DELETE",
    }),
  createScenario: (
    collectionId: string,
    body: {
      slug: string;
      menuTitle: string;
      menuSubtitle?: string;
      setting?: string;
    },
  ) =>
    request<{ scenario: DialogueScenario }>(
      `/api/content/dialogues/${collectionId}/scenarios`,
      { method: "POST", body: JSON.stringify(body) },
    ),
  getScenario: (collectionId: string, slug: string) =>
    request<{ scenario: DialogueScenario }>(
      `/api/content/dialogues/${collectionId}/scenarios/${slug}`,
    ),
  updateScenario: (
    collectionId: string,
    slug: string,
    body: Partial<Omit<DialogueScenario, "id" | "collectionId" | "updatedAt">>,
  ) =>
    request<{ scenario: DialogueScenario }>(
      `/api/content/dialogues/${collectionId}/scenarios/${slug}`,
      { method: "PATCH", body: JSON.stringify(body) },
    ),
  deleteScenario: (collectionId: string, slug: string) =>
    request<{ ok: true }>(
      `/api/content/dialogues/${collectionId}/scenarios/${slug}`,
      { method: "DELETE" },
    ),
  importCollection: async (file: File) => {
    const formData = new FormData();
    formData.append("file", file);
    const res = await fetch("/api/content/dialogues/import", {
      method: "POST",
      body: formData,
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(
        typeof body?.error === "string" ? body.error : "Import failed",
      );
    }
    return res.json() as Promise<{
      collectionId: string;
      scenarioCount: number;
      title: string;
    }>;
  },
  generateLines: (body: {
    prompt: string;
    collectionId?: string;
    setting?: string;
    speakerNames?: string[];
    grammarPointIds?: string[];
    existingLines?: DialogueLine[];
    mode: "replace" | "append";
    lineCount?: number;
    variantIndex?: number;
    variantCount?: number;
    difficulty?: "beginner" | "intermediate" | "advanced" | "expert";
    formality?: "casual" | "polite" | "formal" | "very-formal";
  }) =>
    request<{ generated: GeneratedLines }>(
      "/api/content/dialogues/generate-lines",
      { method: "POST", body: JSON.stringify(body) },
    ),
  generateScenario: (body: {
    prompt: string;
    collectionId?: string;
    existingSlugs?: string[];
    difficulty?: "beginner" | "intermediate" | "advanced" | "expert";
    formality?: "casual" | "polite" | "formal" | "very-formal";
  }) =>
    request<{ generated: GeneratedScenario }>(
      "/api/content/dialogues/generate-scenario",
      { method: "POST", body: JSON.stringify(body) },
    ),
  getScenarioAudio: (collectionId: string, slug: string) =>
    request<ScenarioAudio>(
      `/api/content/dialogues/${collectionId}/scenarios/${slug}/audio`,
    ),
  ensureScenarioAudio: (
    collectionId: string,
    slug: string,
    body: { speaker1Voice?: string; speaker2Voice?: string } = {},
  ) =>
    request<ScenarioAudio>(
      `/api/content/dialogues/${collectionId}/scenarios/${slug}/audio`,
      { method: "POST", body: JSON.stringify(body) },
    ),
  reviseLines: (body: {
    lines: DialogueLine[];
    scope: "selection" | "all";
    selectedIndices?: number[];
    instructions: string;
    setting?: string;
    menuTitle?: string;
    grammarPointIds?: string[];
    difficulty?: "beginner" | "intermediate" | "advanced" | "expert";
    formality?: "casual" | "polite" | "formal" | "very-formal";
  }) =>
    request<{ result: ReviseLinesResult }>(
      "/api/content/dialogues/revise-lines",
      { method: "POST", body: JSON.stringify(body) },
    ),
  extractHighlights: (body: {
    lines: DialogueLine[];
    setting?: string;
    menuTitle?: string;
    grammarPointIds?: string[];
  }) =>
    request<{ extracted: ExtractedHighlights }>(
      "/api/content/dialogues/extract-highlights",
      { method: "POST", body: JSON.stringify(body) },
    ),
  generateQuiz: (body: {
    lines: DialogueLine[];
    setting?: string;
    menuTitle?: string;
    existingQuiz?: QuizQuestion[];
    count?: number;
  }) =>
    request<{ generated: GeneratedQuiz }>(
      "/api/content/dialogues/generate-quiz",
      { method: "POST", body: JSON.stringify(body) },
    ),
  auditScenario: (body: {
    lines: DialogueLine[];
    highlights?: DialogueHighlights | null;
    grammarPointIds?: string[];
    setting?: string;
    menuTitle?: string;
  }) =>
    request<{ result: AuditScenarioResult }>("/api/content/dialogues/audit", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  sanitizeGrammarTags: (body: {
    lines: DialogueLine[];
    highlights?: DialogueHighlights | null;
    grammarPointIds?: string[];
  }) =>
    request<{ result: SanitizeGrammarResult }>(
      "/api/content/dialogues/sanitize-grammar",
      { method: "POST", body: JSON.stringify(body) },
    ),
  audioStatus: (collectionId: string) =>
    request<{ scenarios: ScenarioAudioStatus[] }>(
      `/api/content/dialogues/${collectionId}/audio-status`,
    ),
  publishScenario: (collectionId: string, slug: string) =>
    request<{
      scenario: DialogueScenario;
      publishedAudioUrl: string;
      objectKey: string;
    }>(`/api/content/dialogues/${collectionId}/scenarios/${slug}/publish`, {
      method: "POST",
    }),
  unpublishScenario: (collectionId: string, slug: string) =>
    request<{ scenario: DialogueScenario }>(
      `/api/content/dialogues/${collectionId}/scenarios/${slug}/publish`,
      { method: "DELETE" },
    ),
  publishLesson: (collectionId: string) =>
    request<{
      collectionId: string;
      results: Array<{
        id: string;
        menuTitle: string;
        status: "published" | "unchanged" | "skipped" | "failed";
        publishedAudioUrl: string | null;
        error?: string;
      }>;
      lesson: CollectionFile;
      publishedCount: number;
      skippedCount: number;
      failedCount: number;
    }>(`/api/content/dialogues/${collectionId}/publish`, {
      method: "POST",
    }),
  exportUrl: (collectionId: string) =>
    `/api/content/dialogues/${collectionId}/export`,
  exportZipUrl: (collectionId: string) =>
    `/api/content/dialogues/${collectionId}/export-zip`,
};
