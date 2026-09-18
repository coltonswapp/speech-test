import { NextResponse } from "next/server";
import { desc, eq, sql } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueScenario, ttsProject, ttsVariant } from "@/lib/db/schema";
import { parseVariantTokenSync } from "@/lib/dialogue/token-sync";
import {
  listReviewTiming,
  summarizeReviewTiming,
  type ReviewTiming,
} from "@/lib/dialogue/review-timing";
import type { TokenSyncFlag } from "@/lib/dialogue/types";

export type ReviewQueueLine = {
  lineIndex: number;
  text: string;
  tokens: Array<{ text: string; codes: TokenSyncFlag["code"][] }>;
  lineCodes: TokenSyncFlag["code"][];
};

export type ReviewQueueTake = {
  variantId: string;
  projectId: string;
  createdAt: string;
  voice: string;
  scenarioId: string | null;
  collectionId: string | null;
  slug: string | null;
  title: string;
  isPublishedTake: boolean;
  isSelectedTake: boolean;
  flagCount: number;
  flagsByCode: Partial<Record<TokenSyncFlag["code"], number>>;
  flaggedLines: ReviewQueueLine[];
  lineCount: number;
  tokenCount: number;
  timing: ReviewTiming | null;
};

/** KA-8: every take with source=auto, most flags first, flagged lines inline. */
export async function GET() {
  const rows = await db
    .select({ variant: ttsVariant, project: ttsProject, scenario: dialogueScenario })
    .from(ttsVariant)
    .innerJoin(ttsProject, eq(ttsVariant.projectId, ttsProject.id))
    .leftJoin(dialogueScenario, eq(ttsProject.sourceScenarioId, dialogueScenario.id))
    .where(sql`${ttsVariant.tokenSync}->>'source' = 'auto'`)
    .orderBy(desc(ttsVariant.createdAt));
  const timing = await listReviewTiming();

  const takes: ReviewQueueTake[] = [];
  for (const { variant, project, scenario } of rows) {
    const sync = parseVariantTokenSync(variant.tokenSync);
    if (!sync) continue;
    const flags = sync.flags ?? [];
    const flagsByCode: ReviewQueueTake["flagsByCode"] = {};
    for (const f of flags) flagsByCode[f.code] = (flagsByCode[f.code] ?? 0) + 1;
    const lineIndexes = [...new Set(flags.map((f) => f.lineIndex))].sort((a, b) => a - b);
    const flaggedLines: ReviewQueueLine[] = lineIndexes
      .map((lineIndex) => {
        const line = sync.lines[lineIndex];
        if (!line) return null;
        return {
          lineIndex,
          text: line.text,
          lineCodes: flags.filter((f) => f.lineIndex === lineIndex && f.tokenIndex == null).map((f) => f.code),
          tokens: line.tokens.map((token, tokenIndex) => ({
            text: token.text,
            codes: flags
              .filter((f) => f.lineIndex === lineIndex && f.tokenIndex === tokenIndex)
              .map((f) => f.code),
          })),
        };
      })
      .filter((l): l is ReviewQueueLine => l != null);
    const collectionId = scenario?.collectionId ?? null;
    takes.push({
      variantId: variant.id,
      projectId: project.id,
      createdAt: variant.createdAt.toISOString(),
      voice: variant.voice,
      scenarioId: scenario?.id ?? null,
      collectionId,
      slug: scenario && collectionId ? scenario.id.slice(collectionId.length + 1) : null,
      title: scenario?.menuTitle ?? project.trackName ?? project.id,
      isPublishedTake: scenario?.publishedVariantId === variant.id,
      isSelectedTake: project.selectedVariantId === variant.id,
      flagCount: flags.length,
      flagsByCode,
      flaggedLines,
      lineCount: sync.lines.length,
      tokenCount: sync.lines.reduce((n, l) => n + l.tokens.length, 0),
      timing: timing.get(variant.id) ?? null,
    });
  }
  takes.sort((a, b) => b.flagCount - a.flagCount || b.createdAt.localeCompare(a.createdAt));

  return NextResponse.json({ takes, timing: summarizeReviewTiming(timing.values()) });
}
