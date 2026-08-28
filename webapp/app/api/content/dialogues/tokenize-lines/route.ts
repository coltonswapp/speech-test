import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { tokenizeLinesRequestSchema } from "@/lib/dialogue/types";
import { tokenizeJapaneseLines } from "@/lib/dialogue/gemini-tokenize";
import { DialogueGenerationError } from "@/lib/dialogue/gemini-generate";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = tokenizeLinesRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  try {
    const lines = await tokenizeJapaneseLines(parsed.data.texts);
    return NextResponse.json({ lines });
  } catch (error) {
    if (error instanceof DialogueGenerationError) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
    throw error;
  }
}
