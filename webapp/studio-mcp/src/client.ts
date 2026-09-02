const DEFAULT_BASE_URL = "http://localhost:3000";

export function studioBaseUrl(): string {
  const raw = process.env.STUDIO_BASE_URL?.trim() || DEFAULT_BASE_URL;
  return raw.replace(/\/+$/, "");
}

export class StudioApiError extends Error {
  status: number;
  body: unknown;

  constructor(message: string, status: number, body: unknown) {
    super(message);
    this.name = "StudioApiError";
    this.status = status;
    this.body = body;
  }
}

function formatErrorBody(body: unknown, status: number): string {
  if (body && typeof body === "object") {
    const record = body as Record<string, unknown>;
    if (typeof record.error === "string") return record.error;
    try {
      return JSON.stringify(body);
    } catch {
      return `HTTP ${status}`;
    }
  }
  if (typeof body === "string" && body.trim()) return body;
  return `HTTP ${status}`;
}

export async function studioFetch<T>(
  path: string,
  init: RequestInit & { timeoutMs?: number } = {}
): Promise<T> {
  const { timeoutMs = 30_000, ...rest } = init;
  const url = `${studioBaseUrl()}${path.startsWith("/") ? path : `/${path}`}`;
  const headers = new Headers(rest.headers);
  if (rest.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  const agentToken = process.env.STUDIO_AGENT_TOKEN?.trim();
  if (agentToken && !headers.has("Authorization")) {
    headers.set("Authorization", `Bearer ${agentToken}`);
  }

  const signal = rest.signal ?? AbortSignal.timeout(timeoutMs);
  const res = await fetch(url, { ...rest, headers, signal });
  const text = await res.text();
  let parsed: unknown = null;
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = text;
    }
  }
  if (!res.ok) {
    throw new StudioApiError(formatErrorBody(parsed, res.status), res.status, parsed);
  }
  return parsed as T;
}

export type UnitSummary = {
  id: string;
  title: string;
  subtitle: string | null;
  jlptLevel: number;
  orderIndex: number;
  collections: Array<{ id: string; unitId: string | null; title: string }>;
};

export type ScenarioSummary = {
  id: string;
  collectionId: string;
  orderIndex: number;
  menuTitle: string;
  menuSubtitle: string | null;
  publishedAudioUrl: string | null;
  publishedAt: string | null;
};

export type CollectionSummary = {
  id: string;
  unitId: string | null;
  title: string;
  subtitle: string | null;
  orderIndex: number;
  castVoices: CastVoiceEntry[];
  scenarios: ScenarioSummary[];
};

export type SpokenLine = {
  type?: "spoken";
  speaker: string;
  japanese: string;
  romaji?: string;
  english?: string;
  id?: string;
  grammarPointIDs?: string[];
};

export type StageLine = {
  type: "stage";
  text: string;
  visibility: "cold" | "practice";
  id?: string;
};

export type DialogueLine = SpokenLine | StageLine;

export function isStageLine(line: DialogueLine): line is StageLine {
  return line.type === "stage";
}

export function isSpokenLine(line: DialogueLine): line is SpokenLine {
  return line.type !== "stage";
}

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
  highlights: unknown;
  quiz: unknown;
  updatedAt: string;
};

export type CastVoiceEntry = {
  name: string;
  provider: "gemini" | "openai";
  voice: string;
};

export type DialogueCollection = {
  id: string;
  unitId: string | null;
  title: string;
  subtitle: string | null;
  premise: string | null;
  castVoices: CastVoiceEntry[];
  scenarios: DialogueScenario[] | ScenarioSummary[];
};

export type ScenarioAudio = {
  project: { id: string; speaker1Voice?: string | null; speaker2Voice?: string | null } | null;
  currentContentHash: string;
  speakerNames: string[];
  castVoices: CastVoiceEntry[];
  defaultSpeaker1Voice: string;
  defaultSpeaker2Voice: string;
};

export type TtsVariant = {
  id: string;
  projectId: string;
  createdAt: string;
  voice: string;
  provider: string;
  contentHash: string | null;
  isSelected?: boolean;
};

export function scenarioSlug(scenario: { id: string; collectionId: string }): string {
  return scenario.id.slice(scenario.collectionId.length + 1);
}

export function isUnpublished(scenario: {
  publishedAudioUrl?: string | null;
  publishedAt?: string | null;
}): boolean {
  return !scenario.publishedAudioUrl && !scenario.publishedAt;
}
