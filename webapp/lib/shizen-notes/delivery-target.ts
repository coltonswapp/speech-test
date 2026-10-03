/**
 * Resolves Shohei's delivery URL and outbound auth headers from env.
 * Pure so unit tests can cover missing-URL / missing-key without hitting fetch.
 */
export type ShoheiDeliveryTarget =
  | {
      ok: true;
      url: string;
      headers: { "Content-Type": string; Authorization: string };
    }
  | { ok: false; error: string };

export function resolveShoheiDeliveryTarget(
  env: NodeJS.ProcessEnv = process.env,
): ShoheiDeliveryTarget {
  const url = env.SHOHEI_DELIVERY_URL?.trim();
  if (!url) {
    return { ok: false, error: "SHOHEI_DELIVERY_URL is not set" };
  }

  const key = env.SHOHEI_WEBHOOK_KEY?.trim();
  if (!key) {
    return { ok: false, error: "SHOHEI_WEBHOOK_KEY is not set" };
  }

  return {
    ok: true,
    url,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
  };
}
