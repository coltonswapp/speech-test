/** Thrown by feature input parsers; the route turns it into 400 `invalid_request`. */
export class InputError extends Error {}

export type Body = Record<string, unknown>;

export function requiredString(body: Body, key: string, maxLength: number): string {
  const value = body[key];
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (!trimmed || trimmed.length > maxLength) {
    throw new InputError(`${key} must be a non-empty string (max ${maxLength} chars)`);
  }
  return trimmed;
}

/** Optional hint text: trimmed and truncated rather than rejected. */
export function optionalString(body: Body, key: string, maxLength: number): string | undefined {
  const value = body[key];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new InputError(`${key} must be a string`);
  }
  return value.trim().slice(0, maxLength) || undefined;
}

export function optionalBoolean(body: Body, key: string): boolean {
  const value = body[key];
  if (value === undefined || value === null) return false;
  if (typeof value !== "boolean") {
    throw new InputError(`${key} must be a boolean`);
  }
  return value;
}

export function oneOf<T extends string>(body: Body, key: string, allowed: readonly T[]): T {
  const value = body[key];
  if (typeof value !== "string" || !(allowed as readonly string[]).includes(value)) {
    throw new InputError(`${key} must be one of: ${allowed.join(", ")}`);
  }
  return value as T;
}

export function stringArray(
  body: Body,
  key: string,
  { minCount, maxCount, maxLength }: { minCount: number; maxCount: number; maxLength: number },
): string[] {
  const value = body[key];
  if (!Array.isArray(value)) {
    throw new InputError(`${key} must be an array of strings`);
  }
  const items = value.map((item) => (typeof item === "string" ? item.trim() : ""));
  if (items.length < minCount || items.length > maxCount || items.some((item) => !item || item.length > maxLength)) {
    throw new InputError(
      `${key} must have ${minCount}-${maxCount} non-empty strings (max ${maxLength} chars each)`,
    );
  }
  return items;
}

export function objectArray(body: Body, key: string, maxCount: number): Body[] {
  const value = body[key];
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > maxCount || value.some((item) => !isObject(item))) {
    throw new InputError(`${key} must be an array of at most ${maxCount} objects`);
  }
  return value as Body[];
}

export function isObject(value: unknown): value is Body {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Parses model JSON output into an object; throws on anything else. */
export function parseJSONObject(json: string): Body {
  const parsed: unknown = JSON.parse(json);
  if (!isObject(parsed)) {
    throw new Error("model output is not a JSON object");
  }
  return parsed;
}

export function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

const JAPANESE = /[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF]/;

/** Keeps a phrase that actually shows Japanese. Drops English-only labels. */
export function withJapanese(text: string): string {
  return JAPANESE.test(text) ? text : "";
}

/**
 * "the verb to work" / "the verb, to move" / `the verb "to work"` → "to work".
 * A note that is only a part of speech ("the verb") becomes empty.
 */
export function withoutVerbLabel(text: string): string {
  const quoted =
    /\b(?:the|a)\s+verb\s*(?:[,:;]|meaning|that\s+means)?\s*["“‘']\s*(to\b[^"”’'\n)]*)["”’']/gi;
  const plain = /\b(?:the|a)\s+verb\s*(?:[,:;]|meaning|that\s+means)?\s*(?=to\b)/gi;
  const stripped = text.replace(quoted, "$1").replace(plain, "");
  const bare = stripped.replace(/^\s*(?:the|a)\s+(?:verb|noun|adjective|adverb)\s*[.…]?\s*$/i, "");
  return bare.replace(/[ \t]{2,}/g, " ").trim();
}
