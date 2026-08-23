// Shared N5 teaching-pattern seed: parse CSV + insert-only upsert.
// Pattern ids should eventually align with grammarPoint ids so scenario /
// line grammarPointIds tags can drive linkedScenarioCount in the studio.

import { readFile } from "node:fs/promises";
import path from "node:path";
import { inArray } from "drizzle-orm";
import type { PostgresJsDatabase } from "drizzle-orm/postgres-js";
import { teachingPattern } from "@/lib/db/schema";
import type * as schema from "@/lib/db/schema";

export const N5_PATTERNS_CSV = path.resolve(
  process.cwd(),
  "content/seeds/n5-teaching-patterns.csv"
);

export type TeachingPatternSeedRow = {
  id: string;
  form: string;
  gloss: string;
  jlptBand: number;
  category: string;
  status: string;
  orderIndex: number;
};

type Db = PostgresJsDatabase<typeof schema>;

/** Minimal RFC4180-ish CSV parse (quoted fields, commas, newlines). */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let i = 0;
  let inQuotes = false;
  const s = text.replace(/^\uFEFF/, "");
  while (i < s.length) {
    const ch = s[i];
    if (inQuotes) {
      if (ch === '"') {
        if (s[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field += ch;
      i++;
      continue;
    }
    if (ch === '"') {
      inQuotes = true;
      i++;
      continue;
    }
    if (ch === ",") {
      row.push(field);
      field = "";
      i++;
      continue;
    }
    if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && s[i + 1] === "\n") i++;
      row.push(field);
      field = "";
      if (row.some((cell) => cell.length > 0)) rows.push(row);
      row = [];
      i++;
      continue;
    }
    field += ch;
    i++;
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    if (row.some((cell) => cell.length > 0)) rows.push(row);
  }
  return rows;
}

export function rowsFromCsv(text: string): TeachingPatternSeedRow[] {
  const table = parseCsv(text);
  if (table.length === 0) return [];
  const header = table[0].map((h) => h.trim());
  const idx = (name: string) => {
    const i = header.indexOf(name);
    if (i < 0) throw new Error(`CSV missing column: ${name}`);
    return i;
  };
  const col = {
    id: idx("id"),
    form: idx("form"),
    gloss: idx("gloss"),
    jlptBand: idx("jlptBand"),
    category: idx("category"),
    status: idx("status"),
    orderIndex: idx("orderIndex"),
  };
  return table.slice(1).map((cells, rowIndex) => {
    const id = cells[col.id]?.trim();
    if (!id) throw new Error(`CSV row ${rowIndex + 2}: empty id`);
    return {
      id,
      form: cells[col.form]?.trim() ?? "",
      gloss: cells[col.gloss]?.trim() ?? "",
      jlptBand: (() => {
        const rawBand = (cells[col.jlptBand] ?? "5").trim();
        if (/^n?\d+$/i.test(rawBand)) {
          const n = Number(rawBand.replace(/^n/i, ""));
          return Number.isFinite(n) && n > 0 ? n : 5;
        }
        const n = Number(rawBand);
        return Number.isFinite(n) && n > 0 ? n : 5;
      })(),
      category: cells[col.category]?.trim() ?? "other",
      status: cells[col.status]?.trim() || "seed",
      orderIndex: Number(cells[col.orderIndex] ?? rowIndex) || 0,
    };
  });
}

export async function loadSeedRowsFromDisk(
  csvPath: string = N5_PATTERNS_CSV
): Promise<TeachingPatternSeedRow[]> {
  const text = await readFile(csvPath, "utf-8");
  return rowsFromCsv(text);
}

/**
 * Insert missing patterns only. Existing rows are left untouched so studio
 * edits to gloss/category/status survive re-imports.
 */
export async function upsertTeachingPatterns(
  db: Db,
  rows: TeachingPatternSeedRow[]
): Promise<{ inserted: number; skipped: number; total: number }> {
  if (rows.length === 0) {
    return { inserted: 0, skipped: 0, total: 0 };
  }

  const ids = rows.map((r) => r.id);
  const existing = await db
    .select({ id: teachingPattern.id })
    .from(teachingPattern)
    .where(inArray(teachingPattern.id, ids));
  const existingIds = new Set(existing.map((r) => r.id));

  const toInsert = rows.filter((r) => !existingIds.has(r.id));
  if (toInsert.length > 0) {
    await db.insert(teachingPattern).values(
      toInsert.map((r) => ({
        id: r.id,
        form: r.form,
        gloss: r.gloss,
        jlptBand: r.jlptBand,
        category: r.category,
        status: r.status,
        orderIndex: r.orderIndex,
        updatedAt: new Date(),
      }))
    );
  }

  return {
    inserted: toInsert.length,
    skipped: rows.length - toInsert.length,
    total: rows.length,
  };
}
