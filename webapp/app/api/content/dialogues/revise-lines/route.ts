import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { grammarPoint } from "@/lib/db/schema";
import { reviseLinesRequestSchema } from "@/lib/dialogue/types";
import { DialogueGenerationError } from "@/lib/dialogue/gemini-generate";
import { reviseDialogueLines } from "@/lib/dialogue/gemini-revise";
import { fetchGrammarPointIdSet } from "@/lib/dialogue/grammar-catalog";
import { sanitizeGeneratedLine } from "@/lib/dialogue/sanitize-grammar-tags";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = reviseLinesRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const grammarPointIds = parsed.data.grammarPointIds ?? [];
  const [grammarPointContext, approvedIds] = await Promise.all([
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
    fetchGrammarPointIdSet(),
  ]);

  try {
    const result = await reviseDialogueLines({
      lines: parsed.data.lines,
      scope: parsed.data.scope,
      selectedIndices: parsed.data.selectedIndices,
      instructions: parsed.data.instructions,
      setting: parsed.data.setting,
      menuTitle: parsed.data.menuTitle,
      grammarPointContext,
      difficulty: parsed.data.difficulty,
      formality: parsed.data.formality,
    });

    if (result.scope === "selection") {
      return NextResponse.json({
        result: {
          scope: "selection",
          revisions: result.revisions.map((revision) => ({
            index: revision.index,
            line: sanitizeGeneratedLine(revision.line, approvedIds),
          })),
        },
      });
    }
    return NextResponse.json({
      result: {
        scope: "all",
        generated: {
          ...result.generated,
          lines: result.generated.lines.map((line) =>
            sanitizeGeneratedLine(line, approvedIds)
          ),
        },
      },
    });
  } catch (error) {
    if (error instanceof DialogueGenerationError) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
    throw error;
  }
}
