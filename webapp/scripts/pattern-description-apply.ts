// Apply filled textbook-style descriptions onto teaching_pattern rows.
// Run from webapp/:
//   pnpm dotenv -e .env.local -- tsx scripts/pattern-description-apply.ts --input ../pattern-descriptions/filled.json
//   pnpm dotenv -e .env.local -- tsx scripts/pattern-description-apply.ts --input … --dry-run
//
// Does not invent descriptions. Skips empty description fields and unknown ids.

import { readFile } from "node:fs/promises";
import path from "node:path";
import { eq } from "drizzle-orm";
import { db } from "../lib/db/standalone-client";
import { teachingPattern } from "../lib/db/schema";
import {
  normalizePatternDescriptionFills,
  patternDescriptionFillFileSchema,
} from "../lib/patterns/description-backfill";

function parseArgs(argv: string[]) {
  let inputPath: string | undefined;
  let dryRun = false;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--dry-run") {
      dryRun = true;
      continue;
    }
    if (arg === "--input") {
      inputPath = argv[++i];
      continue;
    }
    if (arg.startsWith("--input=")) {
      inputPath = arg.slice("--input=".length);
    }
  }
  if (!inputPath) {
    throw new Error(
      "Usage: tsx scripts/pattern-description-apply.ts --input <path> [--dry-run]"
    );
  }
  return {
    inputPath: path.resolve(process.cwd(), inputPath),
    dryRun,
  };
}

async function main() {
  const { inputPath, dryRun } = parseArgs(process.argv.slice(2));
  const raw = await readFile(inputPath, "utf8");
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    throw new Error(`Invalid JSON: ${inputPath}`);
  }

  const parsed = patternDescriptionFillFileSchema.safeParse(json);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    throw new Error(
      issue
        ? `${issue.path.join(".") || "body"}: ${issue.message}`
        : "Invalid description fill file"
    );
  }

  const { fills, skippedEmpty } = normalizePatternDescriptionFills(parsed.data);
  const known = await db.query.teachingPattern.findMany({
    columns: { id: true, description: true },
  });
  const byId = new Map(known.map((row) => [row.id, row]));

  let applied = 0;
  let skippedUnknown = 0;

  for (const fill of fills) {
    const existing = byId.get(fill.id);
    if (!existing) {
      skippedUnknown += 1;
      console.warn(`Skip unknown pattern id "${fill.id}"`);
      continue;
    }

    if (dryRun) {
      console.log(`${fill.id}: would set description (dry-run)`);
    } else {
      await db
        .update(teachingPattern)
        .set({
          description: fill.description,
          updatedAt: new Date(),
        })
        .where(eq(teachingPattern.id, fill.id));
      console.log(`${fill.id}: set description`);
    }
    applied += 1;
  }

  console.log(
    `${dryRun ? "Dry-run" : "Done"}: ${applied} description(s), ${skippedEmpty} empty skipped, ${skippedUnknown} unknown id(s).`
  );
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
