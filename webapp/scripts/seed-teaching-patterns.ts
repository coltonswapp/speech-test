// Seed teaching_pattern from content/seeds/n5-teaching-patterns.csv.
// Run with: npm run db:seed-patterns
//
// Idempotent — inserts missing ids only; never overwrites existing rows.

import { db } from "../lib/db/standalone-client";
import { upsertTeachingPatternsFromSeedFile } from "../lib/patterns/import";

async function main() {
  const result = await upsertTeachingPatternsFromSeedFile(db);
  console.log(
    `Teaching patterns: inserted ${result.inserted}, skipped ${result.skipped}, total ${result.total}.`,
  );
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
