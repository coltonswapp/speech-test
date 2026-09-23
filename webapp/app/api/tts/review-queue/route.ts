import { NextResponse } from "next/server";
import { desc, eq, sql } from "drizzle-orm";
import { db } from "@/lib/db/client";
import {
  dialogueCollection,
  dialogueScenario,
  ttsProject,
  ttsVariant,
} from "@/lib/db/schema";
import { parseVariantTokenSync } from "@/lib/dialogue/token-sync";
import {
  listReviewTiming,
  summarizeReviewTiming,
  type ReviewTiming,
} from "@/lib/dialogue/review-timing";
import type { TokenSyncFlag, VariantTokenSync } from "@/lib/dialogue/types";

export type ReviewQueueLine = {
  lineIndex: number;
  text: string;
  playFromSeconds: number | null;
  playUntilSeconds: number | null;
  tokens: Array<{
    text: string;
    codes: TokenSyncFlag["code"][];
    startSeconds: number | null;
  }>;
  lineCodes: TokenSyncFlag["code"][];
};

export type ReviewQueueTake = {
  variantId: string;
  projectId: string;
  createdAt: string;
  voice: string;
  sampleRate: number;
  audioByteCount: number;
  dialogueLineSwitchSamples: number[] | null;
  scenarioId: string | null;
  collectionId: string | null;
  slug: string | null;
  title: string;
  /** Parent lesson title for grouping; falls back to collectionId. */
  collectionTitle: string | null;
  /** Gate B: lesson visible in the learner app. */
  collectionIsActive: boolean | null;
  isPublishedTake: boolean;
  isSelectedTake: boolean;
  flagCount: number;
  flagsByCode: Partial<Record<TokenSyncFlag["code"], number>>;
  flaggedLines: ReviewQueueLine[];
  /** All spoken lines with stamps — used for Play take karaoke follow. */
  lines: Array<{
    lineIndex: number;
    text: string;
    tokens: Array<{
      text: string;
      codes: TokenSyncFlag["code"][];
      startSeconds: number | null;
    }>;
  }>;
  lineCount: number;
  tokenCount: number;
  timing: ReviewTiming | null;
};

function linePlayWindow(
  sync: VariantTokenSync,
  lineIndex: number,
  sampleRate: number,
  markSamples: number[] | null
): { playFromSeconds: number | null; playUntilSeconds: number | null } {
  const line = sync.lines[lineIndex];
  if (!line) return { playFromSeconds: null, playUntilSeconds: null };

  const stamped = line.tokens
    .map((t) => t.startSeconds)
    .filter((s): s is number => s != null);
  let playFromSeconds: number | null =
    stamped.length > 0 ? Math.max(0, Math.min(...stamped) - 0.25) : null;

  // Prefer line-switch marks when stamps are missing on this line.
  if (playFromSeconds == null && markSamples && markSamples.length > 0 && sampleRate > 0) {
    if (lineIndex === 0) playFromSeconds = 0;
    else if (markSamples[lineIndex - 1] != null) {
      playFromSeconds = Math.max(0, markSamples[lineIndex - 1]! / sampleRate - 0.1);
    }
  }

  let playUntilSeconds: number | null = null;
  if (markSamples && markSamples[lineIndex] != null && sampleRate > 0) {
    playUntilSeconds = markSamples[lineIndex]! / sampleRate + 0.15;
  } else {
    const nextLine = sync.lines[lineIndex + 1];
    const nextStart = nextLine?.tokens
      .map((t) => t.startSeconds)
      .find((s): s is number => s != null);
    if (nextStart != null) {
      playUntilSeconds = nextStart;
    } else if (stamped.length > 0) {
      playUntilSeconds = Math.max(...stamped) + 1.2;
    }
  }

  return { playFromSeconds, playUntilSeconds };
}

/** KA-8: every take with source=auto, stable createdAt order, queue lines inline. */
export async function GET() {
  const rows = await db
    .select({
      variant: ttsVariant,
      project: ttsProject,
      scenario: dialogueScenario,
      collection: dialogueCollection,
    })
    .from(ttsVariant)
    .innerJoin(ttsProject, eq(ttsVariant.projectId, ttsProject.id))
    .leftJoin(dialogueScenario, eq(ttsProject.sourceScenarioId, dialogueScenario.id))
    .leftJoin(
      dialogueCollection,
      eq(dialogueScenario.collectionId, dialogueCollection.id),
    )
    .where(sql`${ttsVariant.tokenSync}->>'source' = 'auto'`)
    .orderBy(desc(ttsVariant.createdAt));
  const timing = await listReviewTiming();

  const takes: ReviewQueueTake[] = [];
  for (const { variant, project, scenario, collection } of rows) {
    const sync = parseVariantTokenSync(variant.tokenSync);
    if (!sync) continue;
    // Already accepted on Audio (Mark reviewed / unflag-all) — flags gone,
    // even if a race left source as auto. Queue is only remaining flags.
    if (!(sync.flags?.length)) continue;
    const flags = sync.flags ?? [];
    const flagsByCode: ReviewQueueTake["flagsByCode"] = {};
    for (const f of flags) flagsByCode[f.code] = (flagsByCode[f.code] ?? 0) + 1;
    const lineIndexes = [...new Set(flags.map((f) => f.lineIndex))].sort((a, b) => a - b);
    const markSamples = variant.dialogueLineSwitchSamples ?? null;
    const flaggedLines: ReviewQueueLine[] = lineIndexes
      .map((lineIndex) => {
        const line = sync.lines[lineIndex];
        if (!line) return null;
        const { playFromSeconds, playUntilSeconds } = linePlayWindow(
          sync,
          lineIndex,
          variant.sampleRate,
          markSamples
        );
        return {
          lineIndex,
          text: line.text,
          playFromSeconds,
          playUntilSeconds,
          lineCodes: flags
            .filter((f) => f.lineIndex === lineIndex && f.tokenIndex == null)
            .map((f) => f.code),
          tokens: line.tokens.map((token, tokenIndex) => ({
            text: token.text,
            startSeconds: token.startSeconds ?? null,
            codes: flags
              .filter((f) => f.lineIndex === lineIndex && f.tokenIndex === tokenIndex)
              .map((f) => f.code),
          })),
        };
      })
      .filter((l): l is ReviewQueueLine => l != null);
    const collectionId = scenario?.collectionId ?? null;
    const lines = sync.lines.map((line, lineIndex) => ({
      lineIndex,
      text: line.text,
      tokens: line.tokens.map((token, tokenIndex) => ({
        text: token.text,
        startSeconds: token.startSeconds ?? null,
        codes: flags
          .filter((f) => f.lineIndex === lineIndex && f.tokenIndex === tokenIndex)
          .map((f) => f.code),
      })),
    }));
    takes.push({
      variantId: variant.id,
      projectId: project.id,
      createdAt: variant.createdAt.toISOString(),
      voice: variant.voice,
      sampleRate: variant.sampleRate,
      audioByteCount: variant.audioByteCount,
      dialogueLineSwitchSamples: markSamples,
      scenarioId: scenario?.id ?? null,
      collectionId,
      slug: scenario && collectionId ? scenario.id.slice(collectionId.length + 1) : null,
      title: scenario?.menuTitle ?? project.trackName ?? project.id,
      collectionTitle: collection?.title ?? null,
      collectionIsActive: collection?.isActive ?? null,
      isPublishedTake: scenario?.publishedVariantId === variant.id,
      isSelectedTake: project.selectedVariantId === variant.id,
      flagCount: flags.length,
      flagsByCode,
      flaggedLines,
      lines,
      lineCount: sync.lines.length,
      tokenCount: sync.lines.reduce((n, l) => n + l.tokens.length, 0),
      timing: timing.get(variant.id) ?? null,
    });
  }
  // Stable order: createdAt only. Do not re-rank by remaining flag count —
  // local line checks must not reshuffle the list under the reviewer.
  takes.sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  return NextResponse.json({ takes, timing: summarizeReviewTiming(timing.values()) });
}
