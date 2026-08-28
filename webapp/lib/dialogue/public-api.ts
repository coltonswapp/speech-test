import { asc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import {
  curriculumUnit,
  dialogueCollection,
  dialogueScenario,
} from "@/lib/db/schema";
import {
  buildCollectionFile,
  type ExportableCollection,
  type ExportableScenario,
} from "@/lib/dialogue/export";

export type PublicDialogueCollectionSummary = {
  id: string;
  unitId: string | null;
  title: string;
  subtitle: string | null;
  sceneImage: string | null;
  thumbnailUrl: string | null;
  orderIndex: number;
  updatedAt: string;
  scenarioCount: number;
};

export type PublicCurriculumUnitSummary = {
  id: string;
  title: string;
  subtitle: string | null;
  jlptLevel: number;
  orderIndex: number;
};

export async function listPublicCurriculumUnits(): Promise<
  PublicCurriculumUnitSummary[]
> {
  const units = await db.query.curriculumUnit.findMany({
    orderBy: [asc(curriculumUnit.orderIndex), asc(curriculumUnit.id)],
  });
  return units.map((unit) => ({
    id: unit.id,
    title: unit.title,
    subtitle: unit.subtitle,
    jlptLevel: unit.jlptLevel,
    orderIndex: unit.orderIndex,
  }));
}

export function toExportableScenario(
  scenario: typeof dialogueScenario.$inferSelect
): ExportableScenario {
  return {
    id: scenario.id,
    orderIndex: scenario.orderIndex,
    menuTitle: scenario.menuTitle,
    menuSubtitle: scenario.menuSubtitle,
    japanese: scenario.japanese,
    romaji: scenario.romaji,
    english: scenario.english,
    targetSubstring: scenario.targetSubstring,
    audioKey: scenario.audioKey,
    publishedAudioUrl: scenario.publishedAudioUrl,
    publishedVariantId: scenario.publishedVariantId,
    publishedContentHash: scenario.publishedContentHash,
    publishedAt: scenario.publishedAt?.toISOString() ?? null,
    grammarPointIds: scenario.grammarPointIds,
    setting: scenario.setting,
    lines: scenario.lines,
    highlights: scenario.highlights,
    quiz: scenario.quiz,
    tokenSync: scenario.tokenSync,
  };
}

export async function listPublicDialogueCollections(): Promise<
  PublicDialogueCollectionSummary[]
> {
  const collections = await db.query.dialogueCollection.findMany({
    orderBy: [asc(dialogueCollection.orderIndex), asc(dialogueCollection.id)],
  });
  const scenarios = await db.query.dialogueScenario.findMany({
    orderBy: [asc(dialogueScenario.orderIndex)],
  });
  const countByCollection = new Map<string, number>();
  for (const scenario of scenarios) {
    countByCollection.set(
      scenario.collectionId,
      (countByCollection.get(scenario.collectionId) ?? 0) + 1
    );
  }
  return collections.map((collection) => ({
    id: collection.id,
    unitId: collection.unitId,
    title: collection.title,
    subtitle: collection.subtitle,
    sceneImage: collection.sceneImage,
    thumbnailUrl: collection.thumbnailUrl,
    orderIndex: collection.orderIndex,
    updatedAt: collection.updatedAt.toISOString(),
    scenarioCount: countByCollection.get(collection.id) ?? 0,
  }));
}

export async function getPublicDialogueCollectionFile(collectionId: string) {
  const collection = await db.query.dialogueCollection.findFirst({
    where: eq(dialogueCollection.id, collectionId),
  });
  if (!collection) return null;

  const scenarios = await db.query.dialogueScenario.findMany({
    where: eq(dialogueScenario.collectionId, collectionId),
    orderBy: [asc(dialogueScenario.orderIndex)],
  });

  const exportableCollection: ExportableCollection = {
    id: collection.id,
    title: collection.title,
    subtitle: collection.subtitle,
    sceneImage: collection.sceneImage,
    thumbnailUrl: collection.thumbnailUrl,
  };

  return buildCollectionFile(
    exportableCollection,
    scenarios.map(toExportableScenario)
  );
}
