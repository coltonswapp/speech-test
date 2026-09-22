import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { generateDeckSchema } from "@/lib/slides/schemas";
import { generateNextDraft } from "@/lib/slides/store";

export async function POST(request: NextRequest) {
  const body = await request.json().catch(() => ({}));
  const parsed = generateDeckSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const kind = parsed.data.kind ?? "spotlight";
  const result = await generateNextDraft(kind);
  if ("skipped" in result) {
    return NextResponse.json({ error: result.reason }, { status: 409 });
  }
  return NextResponse.json(result);
}
