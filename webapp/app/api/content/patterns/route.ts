import { NextResponse } from "next/server";
import { asc } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { dialogueScenario, teachingPattern } from "@/lib/db/schema";
import { dialogueLineSchema } from "@/lib/dialogue/types";

// Pattern library list + linkedScenarioCount computed from existing
// dialogue_scenario.grammarPointIds and line.grammarPointIDs tags.
// Pattern ids should eventually align with grammarPoint ids.

const linesSchema = z.array(dialogueLineSchema);

export async function GET() {
  const [patterns, scenarios] = await Promise.all([
    db.query.teachingPattern.findMany({
      orderBy: [asc(teachingPattern.orderIndex), asc(teachingPattern.id)],
    }),
    db.query.dialogueScenario.findMany({
      columns: {
        id: true,
        grammarPointIds: true,
        lines: true,
      },
    }),
  ]);

  const scenarioIdsByTag = new Map<string, Set<string>>();

  for (const scenario of scenarios) {
    const tags = new Set<string>(scenario.grammarPointIds ?? []);
    const parsed = linesSchema.safeParse(scenario.lines);
    if (parsed.success) {
      for (const line of parsed.data) {
        for (const id of line.grammarPointIDs ?? []) tags.add(id);
      }
    }
    for (const tag of tags) {
      const set = scenarioIdsByTag.get(tag) ?? new Set();
      set.add(scenario.id);
      scenarioIdsByTag.set(tag, set);
    }
  }

  return NextResponse.json({
    patterns: patterns.map((pattern) => ({
      ...pattern,
      linkedScenarioCount: scenarioIdsByTag.get(pattern.id)?.size ?? 0,
    })),
  });
}
