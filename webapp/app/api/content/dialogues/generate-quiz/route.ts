import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { generateQuizRequestSchema } from "@/lib/dialogue/types";
import { DialogueGenerationError } from "@/lib/dialogue/gemini-generate";
import { generateQuizQuestions } from "@/lib/dialogue/gemini-generate-quiz";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = generateQuizRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 },
    );
  }

  try {
    const generated = await generateQuizQuestions(parsed.data);
    return NextResponse.json({ generated });
  } catch (error) {
    if (error instanceof DialogueGenerationError) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
    throw error;
  }
}
