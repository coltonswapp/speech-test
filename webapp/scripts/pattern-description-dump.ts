// Dump Pattern library rows that still need a textbook-style description.
// Run from webapp/:
//   pnpm dotenv -e .env.local -- tsx scripts/pattern-description-dump.ts
//   pnpm dotenv -e .env.local -- tsx scripts/pattern-description-dump.ts --out ../pattern-descriptions/missing.json
//
// Writes JSON of missing rows: id, form, gloss, jlptBand, category, notes, description:""
// Fill description with an external LLM, then apply with pattern-description-apply.ts.

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { asc } from "drizzle-orm";
import { db } from "../lib/db/standalone-client";
import { teachingPattern } from "../lib/db/schema";
import {
  isMissingDescription,
  toDescriptionDumpRow,
} from "../lib/patterns/description-backfill";

const DEFAULT_OUT = path.resolve(
  process.cwd(),
  "..",
  "pattern-descriptions",
  "missing.json"
);

function parseArgs(argv: string[]) {
  let outPath = DEFAULT_OUT;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--out") {
      const next = argv[++i];
      if (!next) throw new Error("Usage: --out <path>");
      outPath = path.resolve(process.cwd(), next);
      continue;
    }
    if (arg.startsWith("--out=")) {
      outPath = path.resolve(process.cwd(), arg.slice("--out=".length));
    }
  }
  return { outPath };
}

async function main() {
  const { outPath } = parseArgs(process.argv.slice(2));

  const patterns = await db.query.teachingPattern.findMany({
    orderBy: [asc(teachingPattern.orderIndex), asc(teachingPattern.id)],
  });
  const missing = patterns
    .filter((row) => isMissingDescription(row.description))
    .map(toDescriptionDumpRow);

  await mkdir(path.dirname(outPath), { recursive: true });
  await writeFile(outPath, `${JSON.stringify(missing, null, 2)}\n`, "utf8");
  console.log(
    `Wrote ${missing.length} pattern(s) missing a description to ${outPath} (${patterns.length} total).`
  );
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
