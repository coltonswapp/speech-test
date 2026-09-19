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
  // FormData must keep Content-Type unset so fetch can attach the multipart boundary.
  if (rest.body && !headers.has("Content-Type") && !(rest.body instanceof FormData)) {
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
  /** Background generate → tokenize → align state; null/undefined when idle. */
  autoStampJob?: {
    status: "queued" | "running" | "done" | "error" | "cancelled";
    message?: string;
    startedAt?: string;
    updatedAt?: string;
    finishedAt?: string;
  } | null;
};

export type TokenSyncFlag = {
  code: "stamp-in-silence" | "script-mismatch" | "reading-fallback" | "no-gap";
  lineIndex: number;
  tokenIndex?: number;
  detail?: string;
};

export type AutoStampTakeResult = {
  variant: TtsVariant;
  flags: TokenSyncFlag[];
  marksDerived: boolean;
  summary: string;
};

/**
 * Time every word of a take from its audio and derive line marks (KA-3).
 * Generating a take already queues this in the background; call it directly
 * to re-run, or with `force` to replace human stamps. Wire as the
 * `auto_stamp_take` MCP tool next to `generate_take`.
 */
export function autoStampTake(
  projectId: string,
  variantId: string,
  options: { force?: boolean } = {}
): Promise<AutoStampTakeResult> {
  return studioFetch<AutoStampTakeResult>(
    `/api/tts/projects/${projectId}/variants/${variantId}/auto-stamp`,
    { method: "POST", body: JSON.stringify(options), timeoutMs: 300_000 }
  );
}

export function scenarioSlug(scenario: { id: string; collectionId: string }): string {
  return scenario.id.slice(scenario.collectionId.length + 1);
}

export function isUnpublished(scenario: {
  publishedAudioUrl?: string | null;
  publishedAt?: string | null;
}): boolean {
  return !scenario.publishedAudioUrl && !scenario.publishedAt;
}

const ALLOWED_THUMBNAIL_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
  "image/gif",
]);

const MAX_THUMBNAIL_BYTES = 5 * 1024 * 1024;

export type ThumbnailImageInput = {
  imageUrl?: string;
  imageBase64?: string;
  contentType?: string;
  filename?: string;
};

export type LessonThumbnailResult = {
  collection: DialogueCollection;
  thumbnailUrl: string;
  thumbnailSmallUrl?: string;
  objectKey?: string;
};

export type SceneThumbnailResult = {
  scenario: DialogueScenario;
  thumbnailUrl: string;
  thumbnailSmallUrl?: string;
  objectKey?: string;
};

function normalizeMime(raw: string): string {
  return raw.trim().toLowerCase().split(";")[0]?.trim() ?? "";
}

function mimeFromFilename(filename: string): string | null {
  const ext = filename.split(".").pop()?.toLowerCase();
  switch (ext) {
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "png":
      return "image/png";
    case "webp":
      return "image/webp";
    case "gif":
      return "image/gif";
    default:
      return null;
  }
}

function extensionForMime(mime: string): string {
  switch (normalizeMime(mime)) {
    case "image/jpeg":
    case "image/jpg":
      return "jpg";
    case "image/png":
      return "png";
    case "image/webp":
      return "webp";
    case "image/gif":
      return "gif";
    default:
      return "bin";
  }
}

function assertAllowedMime(mime: string): string {
  const normalized = normalizeMime(mime);
  // Studio routes accept image/jpg; normalize to image/jpeg for File.type.
  const canonical = normalized === "image/jpg" ? "image/jpeg" : normalized;
  if (!ALLOWED_THUMBNAIL_TYPES.has(normalized) && !ALLOWED_THUMBNAIL_TYPES.has(canonical)) {
    throw new Error("Use a JPEG, PNG, WebP, or GIF image.");
  }
  return canonical;
}

function assertWithinSize(byteLength: number): void {
  if (byteLength > MAX_THUMBNAIL_BYTES) {
    throw new Error("Thumbnail must be 5 MB or smaller.");
  }
  if (byteLength <= 0) {
    throw new Error("Thumbnail image is empty.");
  }
}

function parseDataUrl(value: string): { mime: string; base64: string } | null {
  const match = /^data:([^;,]+);base64,(.+)$/is.exec(value.trim());
  if (!match) return null;
  return { mime: match[1], base64: match[2] };
}

function stripBase64Padding(value: string): string {
  const trimmed = value.trim();
  const dataUrl = parseDataUrl(trimmed);
  return dataUrl?.base64 ?? trimmed.replace(/\s+/g, "");
}

async function resolveThumbnailFile(input: ThumbnailImageInput): Promise<File> {
  const hasUrl = typeof input.imageUrl === "string" && input.imageUrl.trim().length > 0;
  const hasBase64 =
    typeof input.imageBase64 === "string" && input.imageBase64.trim().length > 0;

  if (hasUrl === hasBase64) {
    throw new Error("Provide exactly one of imageUrl or imageBase64.");
  }

  let bytes: Buffer;
  let contentType: string | undefined =
    typeof input.contentType === "string" && input.contentType.trim()
      ? input.contentType
      : undefined;
  let filename =
    typeof input.filename === "string" && input.filename.trim()
      ? input.filename.trim()
      : undefined;

  if (hasUrl) {
    const url = input.imageUrl!.trim();
    let parsed: URL;
    try {
      parsed = new URL(url);
    } catch {
      throw new Error("imageUrl must be a valid HTTP(S) URL.");
    }
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      throw new Error("imageUrl must be an HTTP(S) URL.");
    }
    const res = await fetch(url, { signal: AbortSignal.timeout(60_000) });
    if (!res.ok) {
      throw new Error(`Failed to fetch imageUrl (HTTP ${res.status}).`);
    }
    const remoteType = res.headers.get("content-type") ?? undefined;
    const remoteMime = remoteType ? normalizeMime(remoteType) : "";
    const remoteLooksLikeImage =
      remoteMime.startsWith("image/") &&
      (ALLOWED_THUMBNAIL_TYPES.has(remoteMime) ||
        ALLOWED_THUMBNAIL_TYPES.has(
          remoteMime === "image/jpg" ? "image/jpeg" : remoteMime
        ));
    contentType =
      contentType ??
      (remoteLooksLikeImage ? remoteType! : undefined) ??
      (filename ? mimeFromFilename(filename) ?? undefined : undefined) ??
      (mimeFromFilename(parsed.pathname) ?? undefined);
    const arrayBuffer = await res.arrayBuffer();
    bytes = Buffer.from(arrayBuffer);
    if (!filename) {
      const pathName = parsed.pathname.split("/").pop() || "thumbnail";
      filename = pathName.includes(".") ? pathName : undefined;
    }
  } else {
    const raw = input.imageBase64!.trim();
    const dataUrl = parseDataUrl(raw);
    if (dataUrl) {
      contentType = contentType ?? dataUrl.mime;
    }
    if (!contentType && filename) {
      contentType = mimeFromFilename(filename) ?? undefined;
    }
    if (!contentType) {
      throw new Error(
        "imageBase64 requires contentType (or a data URL / filename with a known extension)."
      );
    }
    try {
      bytes = Buffer.from(stripBase64Padding(raw), "base64");
    } catch {
      throw new Error("imageBase64 is not valid base64.");
    }
  }

  if (!contentType) {
    throw new Error("Could not determine image content type.");
  }
  const mime = assertAllowedMime(contentType);
  assertWithinSize(bytes.byteLength);

  const finalName =
    filename && filename.includes(".")
      ? filename
      : `thumbnail.${extensionForMime(mime)}`;

  return new File([bytes], finalName, { type: mime });
}

async function postThumbnailFormData<T>(path: string, file: File): Promise<T> {
  const formData = new FormData();
  formData.append("file", file);
  return studioFetch<T>(path, {
    method: "POST",
    body: formData,
    timeoutMs: 120_000,
  });
}

/** Upload a lesson (collection) card thumbnail. Prefer imageUrl when available. */
export async function setLessonThumbnail(
  collectionId: string,
  image: ThumbnailImageInput
): Promise<LessonThumbnailResult> {
  const file = await resolveThumbnailFile(image);
  return postThumbnailFormData(
    `/api/content/dialogues/${encodeURIComponent(collectionId)}/thumbnail`,
    file
  );
}

/** Clear a lesson (collection) thumbnail. */
export function clearLessonThumbnail(
  collectionId: string
): Promise<{ collection: DialogueCollection }> {
  return studioFetch<{ collection: DialogueCollection }>(
    `/api/content/dialogues/${encodeURIComponent(collectionId)}/thumbnail`,
    { method: "DELETE" }
  );
}

/**
 * Upload a scene (scenario) thumbnail override.
 * When cleared, the app falls back to the lesson/collection thumbnail.
 */
export async function setSceneThumbnail(
  collectionId: string,
  slug: string,
  image: ThumbnailImageInput
): Promise<SceneThumbnailResult> {
  const file = await resolveThumbnailFile(image);
  return postThumbnailFormData(
    `/api/content/dialogues/${encodeURIComponent(collectionId)}/scenarios/${encodeURIComponent(slug)}/thumbnail`,
    file
  );
}

/** Clear a scene thumbnail so the lesson thumbnail applies again. */
export function clearSceneThumbnail(
  collectionId: string,
  slug: string
): Promise<{ scenario: DialogueScenario }> {
  return studioFetch<{ scenario: DialogueScenario }>(
    `/api/content/dialogues/${encodeURIComponent(collectionId)}/scenarios/${encodeURIComponent(slug)}/thumbnail`,
    { method: "DELETE" }
  );
}
