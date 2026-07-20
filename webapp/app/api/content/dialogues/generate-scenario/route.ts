import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueCollection } from "@/lib/db/schema";
import { generateScenarioRequestSchema } from "@/lib/dialogue/types";
import {
  DialogueGenerationError,
  generateScenarioIdea,
} from "@/lib/dialogue/gemini-generate";
import {
  fetchGrammarPointContext,
  filterGrammarPointIdsRequired,
} from "@/lib/dialogue/grammar-catalog";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = generateScenarioRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const [grammarPointCatalog, collection] = await Promise.all([
    fetchGrammarPointContext(),
    parsed.data.collectionId
      ? db.query.dialogueCollection.findFirst({
          where: eq(dialogueCollection.id, parsed.data.collectionId),
          columns: { premise: true },
        })
      : Promise.resolve(null),
  ]);
  const approvedIds = new Set(grammarPointCatalog.map((point) => point.id));

  try {
    const generated = await generateScenarioIdea({
      prompt: parsed.data.prompt,
      premise: collection?.premise ?? undefined,
      existingSlugs: parsed.data.existingSlugs ?? [],
      grammarPointCatalog,
      difficulty: parsed.data.difficulty,
      formality: parsed.data.formality,
    });
    return NextResponse.json({
      generated: {
        ...generated,
        grammarPointIds: filterGrammarPointIdsRequired(
          generated.grammarPointIds ?? [],
          approvedIds
        ),
      },
    });
  } catch (error) {
    if (error instanceof DialogueGenerationError) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
    throw error;
  }
}
