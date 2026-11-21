/**
 * Webhook request shapes for the agent targets. Pure (node:crypto only), so
 * the signature is testable against CSFeedbackKit's RequestSigner.
 */
import { createHmac } from "node:crypto";

/**
 * OpenBot routine webhook headers: HMAC-SHA256 of `timestamp.id.body` with
 * the routine secret, hex, as CSFeedbackKit's RequestSigner (.openbot) does.
 */
export function openBotSignatureHeaders(
  secret: string,
  id: string,
  body: string,
  date: Date,
): Record<string, string> {
  const timestamp = String(Math.floor(date.getTime() / 1000));
  const mac = createHmac("sha256", secret.trim()).update(`${timestamp}.${id}.${body}`).digest("hex");
  return {
    "X-OpenBot-Timestamp": timestamp,
    "X-OpenBot-Delivery-Id": id,
    "X-OpenBot-Signature": `sha256=${mac}`,
  };
}

/** OpenBot's event envelope. */
export function openBotEnvelope(type: string, occurredAt: string, data: unknown): string {
  return JSON.stringify({ type, occurredAt, data });
}

/** Cursor automation (Grok Bot) webhook headers: same as the auto-stamp review webhook. */
export function grokBotHeaders(key: string): Record<string, string> {
  return {
    Authorization: `Bearer ${key}`,
    "X-Automation-Key": key,
  };
}

/** OpenBot rejects bodies past 64 KiB. */
export const WEBHOOK_BODY_LIMIT = 64 * 1024;
