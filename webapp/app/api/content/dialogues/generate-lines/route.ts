import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq, inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueCollection, grammarPoint } from "@/lib/db/schema";
import { generateLinesRequestSchema } from "@/lib/dialogue/types";
import {
  DialogueGenerationError,
  generateDialogueLines,
} from "@/lib/dialogue/gemini-generate";
import { fetchGrammarPointIdSet } from "@/lib/dialogue/grammar-catalog";
import { sanitizeGeneratedLines } from "@/lib/dialogue/sanitize-grammar-tags";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = generateLinesRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const grammarPointIds = parsed.data.grammarPointIds ?? [];
  const [grammarPointContext, approvedIds, collection] = await Promise.all([
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
    parsed.data.collectionId
      ? db.query.dialogueCollection.findFirst({
          where: eq(dialogueCollection.id, parsed.data.collectionId),
          columns: { premise: true },
        })
      : Promise.resolve(null),
  ]);

  try {
    const generated = await generateDialogueLines({
      prompt: parsed.data.prompt,
      premise: collection?.premise ?? undefined,
      setting: parsed.data.setting,
      speakerNames: parsed.data.speakerNames,
      grammarPointContext,
      existingLines: parsed.data.existingLines,
      mode: parsed.data.mode,
      lineCount: parsed.data.lineCount,
      variantIndex: parsed.data.variantIndex,
      variantCount: parsed.data.variantCount,
      difficulty: parsed.data.difficulty,
      formality: parsed.data.formality,
    });
    return NextResponse.json({
      generated: sanitizeGeneratedLines(generated, approvedIds),
    });
  } catch (error) {
    if (error instanceof DialogueGenerationError) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
    throw error;
  }
}
