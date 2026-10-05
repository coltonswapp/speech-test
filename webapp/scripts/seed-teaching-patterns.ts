// Seed teaching_pattern from N5 CSV + added-patterns.json.
// Run with: pnpm db:seed-patterns
//
// Idempotent — inserts missing ids only; never overwrites existing rows.

import { db } from "../lib/db/standalone-client";
import { upsertAllTeachingPatternSeeds } from "../lib/patterns/import";

async function main() {
  const result = await upsertAllTeachingPatternSeeds(db);
  console.log(
    `Teaching patterns: N5 inserted ${result.n5.inserted} / skipped ${result.n5.skipped}; added inserted ${result.added.inserted} / skipped ${result.added.skipped}; total inserted ${result.inserted}.`,
  );
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
