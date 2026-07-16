import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { generateScenarioRequestSchema } from "@/lib/dialogue/types";
import {
  DialogueGenerationError,
  generateScenarioIdea,
} from "@/lib/dialogue/gemini-generate";
import {
  fetchApprovedGrammarPointContext,
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

  const grammarPointCatalog = await fetchApprovedGrammarPointContext();
  const approvedIds = new Set(grammarPointCatalog.map((point) => point.id));

  try {
    const generated = await generateScenarioIdea({
      prompt: parsed.data.prompt,
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
