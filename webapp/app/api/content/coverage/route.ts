import { NextResponse } from "next/server";
import { asc } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import {
  curriculumUnit,
  dialogueCollection,
  dialogueScenario,
  grammarPoint,
} from "@/lib/db/schema";
import { dialogueLineSchema, lineGrammarIds } from "@/lib/dialogue/types";

// Grammar-point coverage across the dialogue catalog: for every point in the
// catalog, which scenarios exercise it (scenario-level tags plus line-level
// tags), with unit/collection context so band gaps are visible at a glance.

export type CoverageScenarioRef = {
  scenarioId: string;
  menuTitle: string;
  collectionId: string;
  collectionTitle: string;
  unitId: string | null;
  unitTitle: string | null;
  jlptLevel: number | null;
  taggedLineCount: number;
};

const linesSchema = z.array(dialogueLineSchema);

export async function GET() {
  const [points, units, collections, scenarios] = await Promise.all([
    db.query.grammarPoint.findMany({
      orderBy: [asc(grammarPoint.orderIndex)],
      columns: {
        id: true,
        orderIndex: true,
        title: true,
        pattern: true,
        headlineEnglish: true,
        status: true,
      },
    }),
    db.query.curriculumUnit.findMany({
      orderBy: [asc(curriculumUnit.orderIndex), asc(curriculumUnit.id)],
    }),
    db.query.dialogueCollection.findMany({
      columns: { id: true, title: true, unitId: true },
    }),
    db.query.dialogueScenario.findMany({
      orderBy: [asc(dialogueScenario.orderIndex)],
      columns: {
        id: true,
        collectionId: true,
        menuTitle: true,
        grammarPointIds: true,
        lines: true,
      },
    }),
  ]);

  const unitById = new Map(units.map((unit) => [unit.id, unit]));
  const collectionById = new Map(
    collections.map((collection) => [collection.id, collection])
  );

  const refsByPoint = new Map<string, CoverageScenarioRef[]>();
  const unknownTags = new Map<string, string[]>(); // tag -> scenario ids
  const knownPointIds = new Set(points.map((point) => point.id));

  for (const scenario of scenarios) {
    const collection = collectionById.get(scenario.collectionId);
    const unit = collection?.unitId
      ? unitById.get(collection.unitId)
      : undefined;

    // Line-level tag counts; scenario-level tags count as coverage even
    // when no individual line is tagged.
    const lineTagCounts = new Map<string, number>();
    const parsedLines = linesSchema.safeParse(scenario.lines);
    if (parsedLines.success) {
      for (const line of parsedLines.data) {
        for (const id of lineGrammarIds(line)) {
          lineTagCounts.set(id, (lineTagCounts.get(id) ?? 0) + 1);
        }
      }
    }
    const taggedIds = new Set([
      ...scenario.grammarPointIds,
      ...lineTagCounts.keys(),
    ]);

    for (const pointId of taggedIds) {
      if (!knownPointIds.has(pointId)) {
        const list = unknownTags.get(pointId) ?? [];
        list.push(scenario.id);
        unknownTags.set(pointId, list);
        continue;
      }
      const refs = refsByPoint.get(pointId) ?? [];
      refs.push({
        scenarioId: scenario.id,
        menuTitle: scenario.menuTitle,
        collectionId: scenario.collectionId,
        collectionTitle: collection?.title ?? scenario.collectionId,
        unitId: unit?.id ?? null,
        unitTitle: unit?.title ?? null,
        jlptLevel: unit?.jlptLevel ?? null,
        taggedLineCount: lineTagCounts.get(pointId) ?? 0,
      });
      refsByPoint.set(pointId, refs);
    }
  }

  const coveredCount = points.filter((point) =>
    refsByPoint.has(point.id)
  ).length;

  return NextResponse.json({
    points: points.map((point) => ({
      ...point,
      coverage: refsByPoint.get(point.id) ?? [],
    })),
    totals: {
      pointCount: points.length,
      coveredCount,
      uncoveredCount: points.length - coveredCount,
      scenarioCount: scenarios.length,
    },
    unknownTags: [...unknownTags.entries()].map(([tag, scenarioIds]) => ({
      tag,
      scenarioIds,
    })),
  });
}
