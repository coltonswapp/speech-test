/** Same published rates as `GeminiPricing` in the iOS app. Unknown models report no cost. */

export type TokenCost = { inputUSD: number; outputUSD: number; totalUSD: number };

const FLASH_36_RATE_CHANGE = Date.UTC(2027, 0, 1);

function rate(model: string, at: Date): { inputPerMillion: number; outputPerMillion: number } | undefined {
  switch (model) {
    case "gemini-2.5-flash":
      return { inputPerMillion: 0.3, outputPerMillion: 2.5 };
    case "gemini-2.5-flash-lite":
      return { inputPerMillion: 0.1, outputPerMillion: 0.4 };
    case "gemini-3.1-flash-lite":
      return { inputPerMillion: 0.25, outputPerMillion: 1.5 };
    case "gemini-3.6-flash":
      if (at.getTime() < FLASH_36_RATE_CHANGE) {
        return { inputPerMillion: 0.75, outputPerMillion: 3.75 };
      }
      return { inputPerMillion: 1.5, outputPerMillion: 7.5 };
    default:
      return undefined;
  }
}

export function estimateCostUSD(
  model: string,
  promptTokens: number,
  outputTokens: number,
  at = new Date(),
): TokenCost | undefined {
  const published = rate(model, at);
  if (!published) return undefined;
  const inputUSD = (promptTokens / 1_000_000) * published.inputPerMillion;
  const outputUSD = (outputTokens / 1_000_000) * published.outputPerMillion;
  return { inputUSD, outputUSD, totalUSD: inputUSD + outputUSD };
}

/** Thinking tokens sit in `total` but not `candidates`; bill the remainder as output. */
export function billedOutputTokens(promptTokens: number, candidatesTokens: number, totalTokens: number): number {
  if (totalTokens > 0) return Math.max(candidatesTokens, totalTokens - promptTokens);
  return candidatesTokens;
}

export function usdToMicros(usd: number): number {
  return Math.round(usd * 1_000_000);
}

export function microsToUSD(micros: number): number {
  return Math.round(micros) / 1_000_000;
}
