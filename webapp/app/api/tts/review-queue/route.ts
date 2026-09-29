import { NextResponse } from "next/server";
import { asc, desc, eq, inArray, sql } from "drizzle-orm";
import { db } from "@/lib/db/client";
import {
  curriculumUnit,
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

/** Sibling take on the same TTS project (same scene). */
export type ReviewQueueSiblingTake = {
  variantId: string;
  createdAt: string;
  /** 1-based index among all takes on the project, oldest → newest. */
  takeIndex: number;
  voice: string;
  audioByteCount: number;
  isPublishedTake: boolean;
  isSelectedTake: boolean;
  /** Still has auto flags (would appear in the queue if not dismissed). */
  inQueue: boolean;
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
  /** Curriculum unit (when the lesson is filed). */
  unitId: string | null;
  unitTitle: string | null;
  /** JLPT path level: 5 = N5, 4 = N4, 3 = N3. */
  jlptLevel: number | null;
  /** 0-based orderIndex among scenes in the lesson. */
  scenarioOrderIndex: number | null;
  /** Scene position among lesson scenes (1-based). */
  scenarioIndex: number | null;
  /** Total scenes in the lesson. */
  scenarioCount: number | null;
  /** 1-based take ordinal among all project takes (oldest → newest). */
  takeIndex: number;
  /** Total takes on this scene's TTS project. */
  takeCount: number;
  siblings: ReviewQueueSiblingTake[];
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
      unit: curriculumUnit,
    })
    .from(ttsVariant)
    .innerJoin(ttsProject, eq(ttsVariant.projectId, ttsProject.id))
    .leftJoin(dialogueScenario, eq(ttsProject.sourceScenarioId, dialogueScenario.id))
    .leftJoin(
      dialogueCollection,
      eq(dialogueScenario.collectionId, dialogueCollection.id),
    )
    .leftJoin(curriculumUnit, eq(dialogueCollection.unitId, curriculumUnit.id))
    .where(sql`${ttsVariant.tokenSync}->>'source' = 'auto'`)
    .orderBy(desc(ttsVariant.createdAt));
  const timing = await listReviewTiming();

  const takes: ReviewQueueTake[] = [];
  for (const { variant, project, scenario, collection, unit } of rows) {
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
      unitId: unit?.id ?? collection?.unitId ?? null,
      unitTitle: unit?.title ?? null,
      jlptLevel: unit?.jlptLevel ?? null,
      scenarioOrderIndex: scenario?.orderIndex ?? null,
      scenarioIndex: null, // filled below
      scenarioCount: null,
      takeIndex: 1,
      takeCount: 1,
      siblings: [],
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

  // Scene index among lesson scenes (1-based by orderIndex).
  const collectionIds = [
    ...new Set(takes.map((t) => t.collectionId).filter((id): id is string => !!id)),
  ];
  if (collectionIds.length > 0) {
    const scenes = await db
      .select({
        id: dialogueScenario.id,
        collectionId: dialogueScenario.collectionId,
        orderIndex: dialogueScenario.orderIndex,
      })
      .from(dialogueScenario)
      .where(inArray(dialogueScenario.collectionId, collectionIds))
      .orderBy(asc(dialogueScenario.orderIndex));
    const byCollection = new Map<string, typeof scenes>();
    for (const scene of scenes) {
      const list = byCollection.get(scene.collectionId) ?? [];
      list.push(scene);
      byCollection.set(scene.collectionId, list);
    }
    for (const take of takes) {
      if (!take.collectionId || !take.scenarioId) continue;
      const list = byCollection.get(take.collectionId) ?? [];
      take.scenarioCount = list.length;
      const idx = list.findIndex((s) => s.id === take.scenarioId);
      take.scenarioIndex = idx >= 0 ? idx + 1 : take.scenarioOrderIndex != null
        ? take.scenarioOrderIndex + 1
        : null;
    }
  }

  // Sibling takes on the same project (multi-take visibility).
  const projectIds = [...new Set(takes.map((t) => t.projectId))];
  if (projectIds.length > 0) {
    const allVariants = await db
      .select({
        id: ttsVariant.id,
        projectId: ttsVariant.projectId,
        createdAt: ttsVariant.createdAt,
        voice: ttsVariant.voice,
        audioByteCount: ttsVariant.audioByteCount,
        tokenSync: ttsVariant.tokenSync,
      })
      .from(ttsVariant)
      .where(inArray(ttsVariant.projectId, projectIds))
      .orderBy(asc(ttsVariant.createdAt));

    const projects = await db
      .select({
        id: ttsProject.id,
        selectedVariantId: ttsProject.selectedVariantId,
        sourceScenarioId: ttsProject.sourceScenarioId,
      })
      .from(ttsProject)
      .where(inArray(ttsProject.id, projectIds));
    const projectById = new Map(projects.map((p) => [p.id, p]));

    const publishedByScenario = new Map<string, string>();
    for (const take of takes) {
      if (take.scenarioId && take.isPublishedTake) {
        publishedByScenario.set(take.scenarioId, take.variantId);
      }
    }
    // Also load publishedVariantId for scenarios we may not have marked above.
    const scenarioIds = [
      ...new Set(
        takes.map((t) => t.scenarioId).filter((id): id is string => !!id),
      ),
    ];
    if (scenarioIds.length > 0) {
      const scenarios = await db
        .select({
          id: dialogueScenario.id,
          publishedVariantId: dialogueScenario.publishedVariantId,
        })
        .from(dialogueScenario)
        .where(inArray(dialogueScenario.id, scenarioIds));
      for (const s of scenarios) {
        if (s.publishedVariantId) {
          publishedByScenario.set(s.id, s.publishedVariantId);
        }
      }
    }

    const variantsByProject = new Map<string, typeof allVariants>();
    for (const v of allVariants) {
      const list = variantsByProject.get(v.projectId) ?? [];
      list.push(v);
      variantsByProject.set(v.projectId, list);
    }

    const queuedIds = new Set(takes.map((t) => t.variantId));

    for (const take of takes) {
      const siblings = variantsByProject.get(take.projectId) ?? [];
      const project = projectById.get(take.projectId);
      const publishedId = take.scenarioId
        ? publishedByScenario.get(take.scenarioId)
        : undefined;
      take.takeCount = siblings.length;
      take.siblings = siblings.map((v, index) => {
        const sync = parseVariantTokenSync(v.tokenSync);
        const inQueue =
          queuedIds.has(v.id) ||
          (sync?.source === "auto" && (sync.flags?.length ?? 0) > 0);
        return {
          variantId: v.id,
          createdAt: v.createdAt.toISOString(),
          takeIndex: index + 1,
          voice: v.voice,
          audioByteCount: v.audioByteCount,
          isPublishedTake: publishedId === v.id,
          isSelectedTake: project?.selectedVariantId === v.id,
          inQueue,
        };
      });
      const self = take.siblings.find((s) => s.variantId === take.variantId);
      take.takeIndex = self?.takeIndex ?? 1;
      take.isPublishedTake = publishedId === take.variantId;
      take.isSelectedTake = project?.selectedVariantId === take.variantId;
    }
  }

  // Stable order: createdAt only. Do not re-rank by remaining flag count —
  // local line checks must not reshuffle the list under the reviewer.
  takes.sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  return NextResponse.json({
    takes,
    timing: summarizeReviewTiming(timing.values()),
  });
}
