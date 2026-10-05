import { NextResponse } from "next/server";
import { asc } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { dialogueScenario, teachingPattern } from "@/lib/db/schema";
import {
  dialogueLineSchema,
  highlightsSchema,
  lineGrammarIds,
} from "@/lib/dialogue/types";
import { upsertTeachingPatterns } from "@/lib/patterns/import";
import {
  normalizeTeachingPatternWrites,
  teachingPatternCreateBodySchema,
} from "@/lib/patterns/schema";

// Pattern library list + create (insert-missing).
// linkedScenarioCount from scenario/line grammar tags and highlight patternIds.

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
        highlights: true,
      },
    }),
  ]);

  const scenarioIdsByTag = new Map<string, Set<string>>();

  for (const scenario of scenarios) {
    const tags = new Set<string>(scenario.grammarPointIds ?? []);
    const parsedLines = linesSchema.safeParse(scenario.lines);
    if (parsedLines.success) {
      for (const line of parsedLines.data) {
        for (const id of lineGrammarIds(line)) tags.add(id);
      }
    }
    const parsedHighlights = highlightsSchema.safeParse(scenario.highlights);
    if (parsedHighlights.success) {
      for (const pattern of parsedHighlights.data.grammarPatterns ?? []) {
        if (pattern.patternId) tags.add(pattern.patternId);
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

/**
 * Create teaching patterns (insert-missing by id).
 * Body: one pattern object, an array, or `{ patterns: [...] }`.
 * Existing ids are left untouched (same discipline as N5 seed import).
 */
export async function POST(request: Request) {
  let json: unknown;
  try {
    json = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const parsed = teachingPatternCreateBodySchema.safeParse(json);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    return NextResponse.json(
      {
        error: issue
          ? `${issue.path.join(".") || "body"}: ${issue.message}`
          : "Invalid pattern body",
      },
      { status: 400 }
    );
  }

  try {
    const rows = normalizeTeachingPatternWrites(parsed.data);
    const result = await upsertTeachingPatterns(db, rows);
    return NextResponse.json(result, {
      status: result.inserted > 0 ? 201 : 200,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Create failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
