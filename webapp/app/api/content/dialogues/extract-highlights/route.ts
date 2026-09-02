import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { grammarPoint } from "@/lib/db/schema";
import {
  extractHighlightsRequestSchema,
  lineGrammarIds,
} from "@/lib/dialogue/types";
import { DialogueGenerationError } from "@/lib/dialogue/gemini-generate";
import { extractDialogueHighlights } from "@/lib/dialogue/gemini-extract-highlights";
import { fetchGrammarPointIdSet } from "@/lib/dialogue/grammar-catalog";
import { sanitizeExtractedHighlights } from "@/lib/dialogue/sanitize-grammar-tags";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = extractHighlightsRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const grammarPointIds = [
    ...new Set([
      ...(parsed.data.grammarPointIds ?? []),
      ...parsed.data.lines.flatMap(lineGrammarIds),
    ]),
  ];

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
    const extracted = await extractDialogueHighlights({
      lines: parsed.data.lines,
      setting: parsed.data.setting,
      menuTitle: parsed.data.menuTitle,
      grammarPointContext,
    });
    return NextResponse.json({
      extracted: sanitizeExtractedHighlights(extracted, approvedIds),
    });
  } catch (error) {
    if (error instanceof DialogueGenerationError) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
    throw error;
  }
}
