import { NextResponse } from "next/server";
import { db } from "@/lib/db/client";
import { upsertTeachingPatternsFromSeedFile } from "@/lib/patterns/import";

// Studio import: upsert N5 seed CSV from disk (insert-missing only).

export async function POST() {
  try {
    const result = await upsertTeachingPatternsFromSeedFile(db);
    return NextResponse.json(result, { status: 201 });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Import failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
