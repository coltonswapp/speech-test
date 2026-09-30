import { createHash, createHmac, timingSafeEqual } from "node:crypto";

import { canonicalJSON } from "./canonical.js";

export const FEEDBACK_TOKEN_TTL_SECONDS = 24 * 60 * 60;

const MIN_KEY_LENGTH = 32;

export type FeedbackTokenParts = {
  uid: string;
  exp: number;
  requestId: string;
  feature: string;
  model: string;
  input: unknown;
  result: unknown;
};

/** Exit if the server-only HMAC secret is missing or short. Never send this to the app. */
export function requireFeedbackHmacKey(): string {
  const value = process.env.LLM_FEEDBACK_HMAC_KEY?.trim() ?? "";
  if (value.length < MIN_KEY_LENGTH) {
    console.error(`LLM_FEEDBACK_HMAC_KEY must be set (at least ${MIN_KEY_LENGTH} characters)`);
    process.exit(1);
  }
  return value;
}

export function retentionDays(): number {
  const raw = process.env.LLM_FEEDBACK_RETENTION_DAYS?.trim();
  if (!raw) return 90;
  const days = Number(raw);
  if (!Number.isInteger(days) || days < 1 || days > 3650) {
    console.error("LLM_FEEDBACK_RETENTION_DAYS must be an integer from 1 to 3650");
    process.exit(1);
  }
  return days;
}

/**
 * `exp.base64url(hmac)`. Binds the Auth uid, expiry, and hashes of canonical input and result.
 * The secret never leaves the gateway, and the token itself is not logged.
 */
export function signFeedbackToken(secret: string, parts: FeedbackTokenParts): string {
  const mac = createHmac("sha256", secret).update(canonicalPayload(parts)).digest();
  return `${parts.exp}.${mac.toString("base64url")}`;
}

export function feedbackExpiry(nowSeconds = Math.floor(Date.now() / 1000)): number {
  return nowSeconds + FEEDBACK_TOKEN_TTL_SECONDS;
}

export type TokenCheck = { ok: true } | { ok: false; reason: "expired" | "rejected" };

/** Recomputes the HMAC over the body the client sent. Uid is the feedback request's Auth uid. */
export function verifyFeedbackToken(secret: string, token: string, parts: Omit<FeedbackTokenParts, "exp">, nowSeconds = Math.floor(Date.now() / 1000)): TokenCheck {
  const dot = token.indexOf(".");
  if (dot <= 0) return { ok: false, reason: "rejected" };
  const expRaw = token.slice(0, dot);
  const macRaw = token.slice(dot + 1);
  if (!/^\d+$/.test(expRaw) || !macRaw) return { ok: false, reason: "rejected" };
  const exp = Number(expRaw);
  if (!Number.isSafeInteger(exp)) return { ok: false, reason: "rejected" };
  if (exp > nowSeconds + FEEDBACK_TOKEN_TTL_SECONDS + 120) return { ok: false, reason: "rejected" };
  if (nowSeconds > exp) return { ok: false, reason: "expired" };

  const expected = createHmac("sha256", secret).update(canonicalPayload({ ...parts, exp })).digest();
  const actual = Buffer.from(macRaw, "base64url");
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    return { ok: false, reason: "rejected" };
  }
  return { ok: true };
}

/** About 1 in 10 thumbs-up docs keep input and result. Thumbs-down always does. Stable per requestId. */
export function storesFeedbackPayload(rating: "up" | "down", requestId: string): boolean {
  if (rating === "down") return true;
  const n = createHash("sha256").update(requestId).digest().readUInt32BE(0);
  return n % 10 === 0;
}

function canonicalPayload(parts: FeedbackTokenParts): string {
  return [
    parts.uid,
    String(parts.exp),
    parts.requestId,
    parts.feature,
    parts.model,
    sha256(canonicalJSON(parts.input)),
    sha256(canonicalJSON(parts.result)),
  ].join("\n");
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
