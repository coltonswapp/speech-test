import "server-only";
import type { ClipAgentTarget } from "@/lib/clip-agent/schema";
import {
  grokBotHeaders,
  openBotEnvelope,
  openBotSignatureHeaders,
  WEBHOOK_BODY_LIMIT,
} from "@/lib/clip-agent/signing";

/**
 * Webhooks that hand a clip report to an agent (docs/clip-agent-tickets-plan.md).
 *
 * Env, per target (a target without both is hidden in Studio):
 * - Grok Bot (Cursor automation): CLIP_AGENT_GROKBOT_WEBHOOK_URL, CLIP_AGENT_GROKBOT_WEBHOOK_KEY
 * - OpenBot routine: CLIP_AGENT_OPENBOT_WEBHOOK_URL, CLIP_AGENT_OPENBOT_WEBHOOK_SECRET
 */

export type AttemptDelivery = {
  ok: boolean;
  /** HTTP status from the target, when it answered. */
  status?: number;
  error?: string;
  at: string;
};

const TIMEOUT_MS = 8_000;
export const ATTEMPT_EVENT_TYPE = "clip-feedback.attempt";

function targetEnv(target: ClipAgentTarget): { url: string; secret: string } | null {
  const prefix = `CLIP_AGENT_${target.toUpperCase()}_WEBHOOK_`;
  const url = process.env[`${prefix}URL`]?.trim();
  const secret = process.env[target === "grokbot" ? `${prefix}KEY` : `${prefix}SECRET`]?.trim();
  return url && secret ? { url, secret } : null;
}

/** Targets with webhook env set, for the Send to agent menu. */
export function configuredAgentTargets(): ClipAgentTarget[] {
  return (["grokbot", "openbot"] as const).filter((t) => targetEnv(t) !== null);
}

/** Posts the attempt to the target. Never throws: the result says what happened. */
export async function deliverAttemptWebhook(
  target: ClipAgentTarget,
  data: { attemptId: string } & Record<string, unknown>,
): Promise<AttemptDelivery> {
  const at = new Date();
  const env = targetEnv(target);
  if (!env) return { ok: false, error: `${target} webhook isn't configured`, at: at.toISOString() };

  let body: string;
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (target === "openbot") {
    body = openBotEnvelope(ATTEMPT_EVENT_TYPE, at.toISOString(), data);
    Object.assign(headers, openBotSignatureHeaders(env.secret, data.attemptId, body, at));
  } else {
    body = JSON.stringify({ type: ATTEMPT_EVENT_TYPE, ...data });
    Object.assign(headers, grokBotHeaders(env.secret));
  }
  if (Buffer.byteLength(body) > WEBHOOK_BODY_LIMIT) {
    return { ok: false, error: `payload is ${Buffer.byteLength(body)} bytes (limit 64 KiB)`, at: at.toISOString() };
  }

  try {
    const res = await fetch(env.url, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (res.ok) return { ok: true, status: res.status, at: at.toISOString() };
    const text = await res.text().catch(() => "");
    return { ok: false, status: res.status, error: text.slice(0, 300) || `HTTP ${res.status}`, at: at.toISOString() };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error), at: at.toISOString() };
  }
}
