// Creates the `clip_feedback` table (lib/db/schema.ts) if it isn't there yet.
// Idempotent. Run once per database before the app ships clip feedback:
//
//   pnpm exec dotenv -e .env.local -- tsx scripts/clip-feedback-table.ts           # dry run
//   pnpm exec dotenv -e .env.local -- tsx scripts/clip-feedback-table.ts --write   # create it
import { sql } from "drizzle-orm";
import { db } from "../lib/db/standalone-client";
import { CLIP_FEEDBACK_DDL } from "../lib/clip-feedback/schema";

async function main() {
  const [{ exists }] = (await db.execute(
    sql`SELECT to_regclass('public.clip_feedback') IS NOT NULL AS exists`,
  )) as unknown as [{ exists: boolean }];
  console.log(`clip_feedback ${exists ? "exists" : "does not exist"}.`);
  if (!process.argv.includes("--write")) {
    console.log("Dry run. Add --write to create the table and indexes (IF NOT EXISTS).");
    process.exit(0);
  }
  await db.execute(sql.raw(CLIP_FEEDBACK_DDL));
  console.log("Done.");
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
