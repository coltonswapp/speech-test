import { NextResponse } from "next/server";
import { db } from "@/lib/db/client";
import { upsertAllTeachingPatternSeeds } from "@/lib/patterns/import";

// Studio import: N5 CSV + added-patterns.json (both insert-missing only).

export async function POST() {
  try {
    const result = await upsertAllTeachingPatternSeeds(db);
    return NextResponse.json(result, {
      status: result.inserted > 0 ? 201 : 200,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Import failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
