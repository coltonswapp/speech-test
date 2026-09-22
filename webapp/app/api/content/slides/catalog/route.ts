import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { searchKanji, searchWords } from "@/lib/slides/catalog";

export async function GET(request: NextRequest) {
  const query = request.nextUrl.searchParams.get("q") ?? "";
  return NextResponse.json({
    kanji: searchKanji(query),
    words: searchWords(query),
  });
}
