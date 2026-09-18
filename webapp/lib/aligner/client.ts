import "server-only";
import { z } from "zod";
import { getSignedDownloadUrl } from "@/lib/storage/r2";

/**
 * Client for the forced-alignment service (services/aligner, deployed on
 * Modal). Env: ALIGNER_URL (base URL), ALIGNER_TOKEN (bearer).
 *
 * Times come back in full-WAV seconds — the same domain as the Studio
 * waveform playhead and the working tokenSync, before any trim.
 */

export const alignerTokenResultSchema = z.object({
  startSeconds: z.number(),
  endSeconds: z.number(),
  score: z.number(),
  readingFallback: z.boolean(),
});
export type AlignerTokenResult = z.infer<typeof alignerTokenResultSchema>;

export const alignerLineResultSchema = z.object({
  tokens: z.array(alignerTokenResultSchema),
  score: z.number(),
});

export const alignerResponseSchema = z.object({
  alignerVersion: z.string(),
  durationSeconds: z.number(),
  sampleRate: z.number(),
  lines: z.array(alignerLineResultSchema),
  timings: z.record(z.string(), z.number()).optional(),
});
export type AlignerResponse = z.infer<typeof alignerResponseSchema>;

export type AlignerLineInput = {
  text: string;
  tokens: Array<{ text: string; reading?: string | null }>;
};

export class AlignerError extends Error {
  constructor(
    message: string,
    readonly status: number | null
  ) {
    super(message);
    this.name = "AlignerError";
  }
}

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new AlignerError(`${name} is not set`, null);
  return value;
}

export function alignerConfigured(): boolean {
  return Boolean(process.env.ALIGNER_URL && process.env.ALIGNER_TOKEN);
}

const SIGNED_URL_TTL_SECONDS = 10 * 60;
const REQUEST_TIMEOUT_MS = 90_000;

/** Align a take's script to its WAV in R2. */
export async function alignVariantAudio(params: {
  audioObjectKey: string;
  lines: AlignerLineInput[];
}): Promise<AlignerResponse> {
  const audioUrl = await getSignedDownloadUrl(
    params.audioObjectKey,
    SIGNED_URL_TTL_SECONDS
  );
  return alignAudioUrl({ audioUrl, lines: params.lines });
}

export async function alignAudioUrl(params: {
  audioUrl: string;
  lines: AlignerLineInput[];
}): Promise<AlignerResponse> {
  const base = requiredEnv("ALIGNER_URL").replace(/\/+$/, "");
  const token = requiredEnv("ALIGNER_TOKEN");
  const body = {
    audioUrl: params.audioUrl,
    lines: params.lines.map((line) => ({
      text: line.text,
      tokens: line.tokens.map((token) => ({
        text: token.text,
        ...(token.reading ? { reading: token.reading } : {}),
      })),
    })),
  };

  let response: Response;
  try {
    response = await fetch(`${base}/align`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  } catch (error) {
    throw new AlignerError(
      `aligner unreachable: ${error instanceof Error ? error.message : String(error)}`,
      null
    );
  }
  if (!response.ok) {
    let detail = response.statusText;
    try {
      const json = (await response.json()) as { detail?: unknown };
      if (typeof json.detail === "string") detail = json.detail;
    } catch {
      // keep statusText
    }
    throw new AlignerError(`aligner ${response.status}: ${detail}`, response.status);
  }
  const parsed = alignerResponseSchema.safeParse(await response.json());
  if (!parsed.success) {
    throw new AlignerError("aligner returned an unexpected payload", response.status);
  }
  const expected = params.lines.map((line) => line.tokens.length);
  const got = parsed.data.lines.map((line) => line.tokens.length);
  if (expected.length !== got.length || expected.some((n, i) => n !== got[i])) {
    throw new AlignerError("aligner token count does not match request", response.status);
  }
  return parsed.data;
}
