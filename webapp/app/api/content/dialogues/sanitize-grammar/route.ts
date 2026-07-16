import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { sanitizeGrammarRequestSchema } from "@/lib/dialogue/types";
import { fetchApprovedGrammarPointIdSet } from "@/lib/dialogue/grammar-catalog";
import {
  countRemovedGrammarTags,
  sanitizeScenarioGrammarTags,
} from "@/lib/dialogue/sanitize-grammar-tags";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = sanitizeGrammarRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const approvedIds = await fetchApprovedGrammarPointIdSet();
  const sanitized = sanitizeScenarioGrammarTags(
    {
      lines: parsed.data.lines,
      highlights: parsed.data.highlights ?? null,
      grammarPointIds: parsed.data.grammarPointIds ?? [],
    },
    approvedIds
  );

  return NextResponse.json({
    result: {
      lines: sanitized.lines,
      highlights: sanitized.highlights,
      grammarPointIds: sanitized.grammarPointIds,
      removedCount: countRemovedGrammarTags(sanitized.removed),
    },
  });
}
