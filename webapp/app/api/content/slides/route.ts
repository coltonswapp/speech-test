import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { findKanji, findWord } from "@/lib/slides/catalog";
import { createDeckSchema } from "@/lib/slides/schemas";
import { createDeckFromSubject, listDecksNewestFirst } from "@/lib/slides/store";

export async function GET() {
  const decks = await listDecksNewestFirst();
  return NextResponse.json({ decks });
}

export async function POST(request: NextRequest) {
  const body = await request.json().catch(() => ({}));
  const parsed = createDeckSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const { kind, subject, recipeId, exportSize, photoSet } = parsed.data;
  if (kind === "spotlight" && !findKanji(subject)) {
    return NextResponse.json({ error: `Unknown kanji “${subject}”.` }, { status: 400 });
  }
  if (kind === "decomposition" && !findWord(subject)) {
    return NextResponse.json({ error: `Unknown word “${subject}”.` }, { status: 400 });
  }
  try {
    const deck = await createDeckFromSubject({
      kind,
      subject,
      recipeId,
      exportSize,
      photoSet,
    });
    return NextResponse.json({ deck });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not create deck.";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
