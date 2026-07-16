import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { db } from "@/lib/db/client";
import { parseCollectionFile, upsertCollectionFile } from "@/lib/dialogue/import";

export async function POST(request: NextRequest) {
  const formData = await request.formData();
  const file = formData.get("file");
  if (!(file instanceof File)) {
    return NextResponse.json({ error: "No file provided" }, { status: 400 });
  }

  const raw = await file.text();
  let parsed;
  try {
    parsed = parseCollectionFile(raw);
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Invalid file." },
      { status: 400 }
    );
  }

  const result = await upsertCollectionFile(db, parsed);
  return NextResponse.json(
    { ...result, title: parsed.title },
    { status: 201 }
  );
}
