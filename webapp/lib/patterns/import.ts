// Re-exports + CSV/JSON upsert API for teaching patterns.
// Implementation lives in ./seed (batch insert-missing).

import { readFile } from "node:fs/promises";
import type { PostgresJsDatabase } from "drizzle-orm/postgres-js";
import type * as schema from "@/lib/db/schema";
import {
  ADDED_PATTERNS_JSON,
  N5_PATTERNS_CSV,
  rowsFromCsv,
  upsertTeachingPatterns,
  type TeachingPatternSeedRow,
} from "./seed";
import {
  teachingPatternWriteSchema,
  type TeachingPatternWrite,
} from "./schema";

export type TeachingPatternRow = TeachingPatternSeedRow;

export type TeachingPatternUpsertResult = {
  inserted: number;
  skipped: number;
  total: number;
  insertedIds: string[];
};

export function parseCsv(raw: string): TeachingPatternRow[] {
  return rowsFromCsv(raw);
}

export async function upsertTeachingPatternsFromCsv(
  db: PostgresJsDatabase<typeof schema>,
  raw: string,
): Promise<TeachingPatternUpsertResult> {
  return upsertTeachingPatterns(db, parseCsv(raw));
}

export async function upsertTeachingPatternsFromSeedFile(
  db: PostgresJsDatabase<typeof schema>,
  csvPath: string = N5_PATTERNS_CSV,
): Promise<TeachingPatternUpsertResult> {
  const raw = await readFile(csvPath, "utf-8");
  return upsertTeachingPatternsFromCsv(db, raw);
}

/** Parse content/seeds/added-patterns.json (`{ patterns: [...] }` or a bare array). */
export function parseAddedPatternsJson(raw: string): TeachingPatternSeedRow[] {
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    throw new Error("added-patterns.json is not valid JSON");
  }
  const rows = Array.isArray(json)
    ? json
    : json &&
        typeof json === "object" &&
        Array.isArray((json as { patterns?: unknown }).patterns)
      ? (json as { patterns: unknown[] }).patterns
      : null;
  if (!rows) {
    throw new Error(
      "added-patterns.json must be an array or { patterns: [...] }"
    );
  }
  return rows.map((row, index) => {
    const parsed = teachingPatternWriteSchema.safeParse(row);
    if (!parsed.success) {
      const issue = parsed.error.issues[0];
      throw new Error(
        `added-patterns.json[${index}]: ${issue?.path.join(".") ?? "?"} ${issue?.message ?? "invalid"}`
      );
    }
    const p: TeachingPatternWrite = parsed.data;
    return {
      id: p.id,
      form: p.form.trim(),
      gloss: p.gloss.trim(),
      jlptBand: p.jlptBand,
      category: p.category.trim() || "other",
      status: p.status.trim() || "seed",
      notes: p.notes?.trim() ? p.notes.trim() : null,
      orderIndex: p.orderIndex,
    };
  });
}

export async function upsertTeachingPatternsFromAddedFile(
  db: PostgresJsDatabase<typeof schema>,
  jsonPath: string = ADDED_PATTERNS_JSON,
): Promise<TeachingPatternUpsertResult> {
  const raw = await readFile(jsonPath, "utf-8");
  return upsertTeachingPatterns(db, parseAddedPatternsJson(raw));
}

/** N5 CSV + added-patterns.json, both insert-missing. */
export async function upsertAllTeachingPatternSeeds(
  db: PostgresJsDatabase<typeof schema>,
): Promise<{
  n5: TeachingPatternUpsertResult;
  added: TeachingPatternUpsertResult;
  inserted: number;
  skipped: number;
  total: number;
}> {
  const n5 = await upsertTeachingPatternsFromSeedFile(db);
  const added = await upsertTeachingPatternsFromAddedFile(db);
  return {
    n5,
    added,
    inserted: n5.inserted + added.inserted,
    skipped: n5.skipped + added.skipped,
    total: n5.total + added.total,
  };
}

export { upsertTeachingPatterns };
