import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { grammarPoint } from "@/lib/db/schema";
import { auditScenarioContent } from "@/lib/dialogue/audit-scenario";
import { fetchApprovedGrammarPointContext } from "@/lib/dialogue/grammar-catalog";
import { auditScenarioRequestSchema } from "@/lib/dialogue/types";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = auditScenarioRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const grammarPointIds = [
    ...new Set([
      ...(parsed.data.grammarPointIds ?? []),
      ...parsed.data.lines.flatMap((line) => line.grammarPointIDs ?? []),
      ...(parsed.data.highlights?.grammarPatterns ?? [])
        .map((p) => p.grammarPointID)
        .filter((id): id is string => !!id),
    ]),
  ];

  const [referencedGrammarPointContext, approvedGrammarPointContext] =
    await Promise.all([
      grammarPointIds.length > 0
        ? db.query.grammarPoint.findMany({
            where: inArray(grammarPoint.id, grammarPointIds),
            columns: {
              id: true,
              title: true,
              pattern: true,
              shortDefinition: true,
            },
          })
        : Promise.resolve([]),
      fetchApprovedGrammarPointContext(),
    ]);

  const grammarPointContext =
    referencedGrammarPointContext.length > 0
      ? referencedGrammarPointContext
      : approvedGrammarPointContext;

  const result = await auditScenarioContent({
    lines: parsed.data.lines,
    highlights: parsed.data.highlights ?? null,
    grammarPointIds: parsed.data.grammarPointIds ?? [],
    setting: parsed.data.setting,
    menuTitle: parsed.data.menuTitle,
    grammarPointContext,
    knownGrammarPointIds: new Set(
      approvedGrammarPointContext.map((point) => point.id)
    ),
  });

  return NextResponse.json({ result });
}
