import "server-only";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import {
  dialogueCollection,
  dialogueScenario,
  ttsProject,
  ttsVariant,
} from "@/lib/db/schema";
import type { TokenSyncFlag } from "@/lib/dialogue/types";

/**
 * Grok Bot webhook when auto-stamp finishes with review-worthy results or fails.
 *
 * Env (missing URL or key → skip notify; never fail the stamp):
 * - AUTO_STAMP_REVIEW_WEBHOOK_URL — full webhook URL
 *   (https://api2.cursor.sh/automations/webhook/...)
 * - AUTO_STAMP_REVIEW_WEBHOOK_KEY — bearer / X-Automation-Key sender key
 * - STUDIO_PUBLIC_BASE_URL — optional deep-link origin
 *   (default https://shizen-studio.vercel.app)
 *
 * lineMarkAttentionCount = count of `no-gap` flags (raised when a derived
 * line mark sits in a too-short silence gap before the next speaker onset).
 * Clean stamps (0 flags, success) stay silent; cancelled jobs never notify.
 */

export type AutoStampReviewWebhookPayload = {
  kind: "auto-stamp-review" | "auto-stamp-failed";
  collectionId: string | null;
  slug: string | null;
  scenarioTitle: string | null;
  collectionTitle: string | null;
  variantId: string;
  projectId: string;
  flagCount: number;
  lineMarkAttentionCount: number;
  summary: string;
  studioUrl: string;
  reviewQueueUrl: string;
  alignSeconds: number | null;
  wallSeconds: number | null;
};

const DEFAULT_STUDIO_PUBLIC_BASE_URL = "https://shizen-studio.vercel.app";
const WEBHOOK_TIMEOUT_MS = 8_000;

let missingEnvLogged = false;

/** Count of line-mark attention flags (`no-gap`). */
export function lineMarkAttentionCount(flags: TokenSyncFlag[]): number {
  return flags.filter((f) => f.code === "no-gap").length;
}

export function studioPublicBaseUrl(): string {
  const raw =
    process.env.STUDIO_PUBLIC_BASE_URL?.trim() || DEFAULT_STUDIO_PUBLIC_BASE_URL;
  return raw.replace(/\/+$/, "");
}

/** Same deep-link shape as review-queue `editorHref`. */
export function buildStudioTakeUrl(params: {
  collectionId: string | null;
  slug: string | null;
  projectId: string;
  variantId: string;
}): string {
  const base = studioPublicBaseUrl();
  if (params.collectionId && params.slug) {
    return `${base}/content/dialogues/${params.collectionId}/${params.slug}?tab=audio&take=${params.variantId}`;
  }
  return `${base}/tts/${params.projectId}?take=${params.variantId}`;
}

export function buildReviewQueueUrl(): string {
  return `${studioPublicBaseUrl()}/tts/review`;
}

export type AutoStampNotifyInput = {
  kind: "auto-stamp-review" | "auto-stamp-failed";
  variantId: string;
  /** Optional when the caller already has it; otherwise resolved from the take. */
  projectId?: string;
  flags?: TokenSyncFlag[];
  summary: string;
  alignSeconds?: number | null;
  wallSeconds?: number | null;
  /** When already loaded (avoids a second project fetch). */
  project?: typeof ttsProject.$inferSelect;
};

/**
 * Fire-and-forget POST after stamps are written (or on failure).
 * Never throws; never blocks the caller beyond scheduling the request.
 */
export function notifyAutoStampReview(input: AutoStampNotifyInput): void {
  void deliverAutoStampReview(input);
}

async function deliverAutoStampReview(input: AutoStampNotifyInput): Promise<void> {
  const url = process.env.AUTO_STAMP_REVIEW_WEBHOOK_URL?.trim();
  const key = process.env.AUTO_STAMP_REVIEW_WEBHOOK_KEY?.trim();
  if (!url || !key) {
    if (!missingEnvLogged) {
      missingEnvLogged = true;
      console.info(
        "[auto-stamp-review-webhook] Skipping notify — AUTO_STAMP_REVIEW_WEBHOOK_URL / KEY not set."
      );
    }
    return;
  }

  try {
    const payload = await buildPayload(input);
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
        "X-Automation-Key": key,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(WEBHOOK_TIMEOUT_MS),
    });
    if (!res.ok) {
      console.error(
        `[auto-stamp-review-webhook] HTTP ${res.status} for ${payload.kind} ${payload.variantId}`
      );
    }
  } catch (error) {
    console.error(
      `[auto-stamp-review-webhook] Failed for ${input.kind} ${input.variantId}:`,
      error
    );
  }
}

async function buildPayload(
  input: AutoStampNotifyInput
): Promise<AutoStampReviewWebhookPayload> {
  const flags = input.flags ?? [];
  const flagCount = flags.length;
  const lmAttention = lineMarkAttentionCount(flags);

  let project = input.project ?? null;
  let projectId = input.projectId ?? project?.id ?? null;
  if (!projectId) {
    const variant = await db.query.ttsVariant.findFirst({
      where: eq(ttsVariant.id, input.variantId),
    });
    projectId = variant?.projectId ?? null;
  }
  if (!project && projectId) {
    project =
      (await db.query.ttsProject.findFirst({
        where: eq(ttsProject.id, projectId),
      })) ?? null;
  }
  // Last resort so the payload always has a projectId field.
  projectId = projectId ?? input.projectId ?? "";

  let collectionId: string | null = null;
  let slug: string | null = null;
  let scenarioTitle: string | null = null;
  let collectionTitle: string | null = null;

  const scenarioId = project?.sourceScenarioId ?? null;
  if (scenarioId) {
    const scenario = await db.query.dialogueScenario.findFirst({
      where: eq(dialogueScenario.id, scenarioId),
    });
    if (scenario) {
      collectionId = scenario.collectionId;
      slug = scenario.id.startsWith(`${scenario.collectionId}/`)
        ? scenario.id.slice(scenario.collectionId.length + 1)
        : null;
      scenarioTitle = scenario.menuTitle;
      const collection = await db.query.dialogueCollection.findFirst({
        where: eq(dialogueCollection.id, scenario.collectionId),
      });
      collectionTitle = collection?.title ?? null;
    }
  }

  if (!scenarioTitle && project) {
    scenarioTitle = project.trackName ?? null;
  }

  return {
    kind: input.kind,
    collectionId,
    slug,
    scenarioTitle,
    collectionTitle,
    variantId: input.variantId,
    projectId,
    flagCount,
    lineMarkAttentionCount: lmAttention,
    summary: input.summary,
    studioUrl: buildStudioTakeUrl({
      collectionId,
      slug,
      projectId,
      variantId: input.variantId,
    }),
    reviewQueueUrl: buildReviewQueueUrl(),
    alignSeconds: input.alignSeconds ?? null,
    wallSeconds: input.wallSeconds ?? null,
  };
}
