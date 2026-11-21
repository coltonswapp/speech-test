import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

/** Bearer tokens issued from Settings → Agent tokens. Matches the env token style. */
export const STUDIO_AGENT_TOKEN_PREFIX = "sat_";
export const STUDIO_AGENT_TOKEN_BYTES = 32;
export const STUDIO_AGENT_TOKEN_DISPLAY_PREFIX_LENGTH = 12;
/** Skip last_used_at writes more often than this (per token). */
export const LAST_USED_TOUCH_MS = 5 * 60 * 1000;
const MAX_PRESENTED_TOKEN_LENGTH = 512;

export type StudioAgentTokenRecord = {
  id: string;
  name: string;
  tokenHash: string;
  prefix: string;
  createdAt: Date;
  lastUsedAt: Date | null;
  revokedAt: Date | null;
};

/** What Studio lists and returns after create — never includes the hash or plaintext. */
export type StudioAgentTokenPublic = {
  id: string;
  name: string;
  prefix: string;
  createdAt: Date;
  lastUsedAt: Date | null;
};

export type StudioAgentTokenStore = {
  insert(row: StudioAgentTokenRecord): Promise<StudioAgentTokenRecord>;
  findActiveByHash(tokenHash: string): Promise<StudioAgentTokenRecord | null>;
  findActiveByName(name: string): Promise<StudioAgentTokenRecord | null>;
  listActive(): Promise<StudioAgentTokenRecord[]>;
  revoke(id: string, at: Date): Promise<StudioAgentTokenRecord | null>;
  touchLastUsed(id: string, at: Date): Promise<void>;
};

export class AgentTokenError extends Error {
  constructor(
    readonly code: "name_taken" | "not_found" | "invalid_name",
    message: string,
  ) {
    super(message);
    this.name = "AgentTokenError";
  }
}

export function hashStudioAgentToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function hashesEqual(a: string, b: string): boolean {
  const left = Buffer.from(a, "hex");
  const right = Buffer.from(b, "hex");
  if (left.length !== right.length) return false;
  return timingSafeEqual(left, right);
}

export function generateStudioAgentToken(
  entropy: () => Buffer = () => randomBytes(STUDIO_AGENT_TOKEN_BYTES),
): { token: string; prefix: string; hash: string } {
  const token = `${STUDIO_AGENT_TOKEN_PREFIX}${entropy().toString("hex")}`;
  return {
    token,
    prefix: token.slice(0, STUDIO_AGENT_TOKEN_DISPLAY_PREFIX_LENGTH),
    hash: hashStudioAgentToken(token),
  };
}

export function newAgentTokenId(
  entropy: () => Buffer = () => randomBytes(9),
): string {
  return `atk_${entropy().toString("base64url")}`;
}

export function normalizeAgentTokenName(name: string): string {
  return name.trim().replace(/\s+/g, " ");
}

export function toPublicAgentToken(row: StudioAgentTokenRecord): StudioAgentTokenPublic {
  return {
    id: row.id,
    name: row.name,
    prefix: row.prefix,
    createdAt: row.createdAt,
    lastUsedAt: row.lastUsedAt,
  };
}

export async function createStudioAgentToken(
  store: StudioAgentTokenStore,
  rawName: string,
  now: () => Date = () => new Date(),
): Promise<{ token: string; tokenRecord: StudioAgentTokenPublic }> {
  const name = normalizeAgentTokenName(rawName);
  if (!name || name.length > 80) {
    throw new AgentTokenError("invalid_name", "Name must be 1–80 characters.");
  }
  if (await store.findActiveByName(name)) {
    throw new AgentTokenError("name_taken", `An active token named “${name}” already exists.`);
  }
  const generated = generateStudioAgentToken();
  const createdAt = now();
  const row = await store.insert({
    id: newAgentTokenId(),
    name,
    tokenHash: generated.hash,
    prefix: generated.prefix,
    createdAt,
    lastUsedAt: null,
    revokedAt: null,
  });
  return { token: generated.token, tokenRecord: toPublicAgentToken(row) };
}

export async function listStudioAgentTokens(
  store: StudioAgentTokenStore,
): Promise<StudioAgentTokenPublic[]> {
  const rows = await store.listActive();
  return rows.map(toPublicAgentToken);
}

export async function revokeStudioAgentToken(
  store: StudioAgentTokenStore,
  id: string,
  now: () => Date = () => new Date(),
): Promise<StudioAgentTokenPublic> {
  const row = await store.revoke(id, now());
  if (!row) throw new AgentTokenError("not_found", "Token not found or already revoked.");
  return toPublicAgentToken(row);
}

/**
 * Hash-lookup of an unrevoked stored token. Updates last_used_at at most once
 * per LAST_USED_TOUCH_MS. Never logs or returns the plaintext.
 */
export async function storedStudioAgentTokenMatches(
  store: StudioAgentTokenStore,
  token: string,
  now: () => Date = () => new Date(),
): Promise<boolean> {
  if (!token || token.length > MAX_PRESENTED_TOKEN_LENGTH) return false;
  const hash = hashStudioAgentToken(token);
  const row = await store.findActiveByHash(hash);
  if (!row || !hashesEqual(row.tokenHash, hash)) return false;
  const at = now();
  const stale =
    !row.lastUsedAt || at.getTime() - row.lastUsedAt.getTime() >= LAST_USED_TOUCH_MS;
  if (stale) {
    try {
      await store.touchLastUsed(row.id, at);
    } catch {
      // Auth succeeded; a last-used write must not fail the request.
    }
  }
  return true;
}
