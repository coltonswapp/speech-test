// One-time cleanup before `pnpm db:push` adds the FK + unique index on
// tts_project.source_scenario_id. Run with:
//   pnpm dotenv -e .env.local -- tsx scripts/cleanup-scenario-links.ts
//
// 1. Unlinks projects whose scenario no longer exists (deleted scenarios,
//    foreign JSON imports) — they survive as ad-hoc tracks.
// 2. Dedupes multiple projects per scenario (keeps the most recently updated).
// 3. Drops now-inert tts_dialogue_line copies of scenario-backed projects —
//    generation reads dialogue_scenario.lines directly.

import { sql } from "drizzle-orm";
import { db } from "../lib/db/standalone-client";

async function main() {
  const orphaned = await db.execute(sql`
    UPDATE tts_project
    SET source_scenario_id = NULL
    WHERE source_scenario_id IS NOT NULL
      AND source_scenario_id NOT IN (SELECT id FROM dialogue_scenario)
  `);
  console.log(`Unlinked ${orphaned.count ?? 0} orphaned project(s).`);

  const deduped = await db.execute(sql`
    UPDATE tts_project
    SET source_scenario_id = NULL
    WHERE source_scenario_id IS NOT NULL
      AND id NOT IN (
        SELECT DISTINCT ON (source_scenario_id) id
        FROM tts_project
        WHERE source_scenario_id IS NOT NULL
        ORDER BY source_scenario_id, updated_at DESC
      )
  `);
  console.log(`Unlinked ${deduped.count ?? 0} duplicate project(s).`);

  const deletedLines = await db.execute(sql`
    DELETE FROM tts_dialogue_line
    WHERE project_id IN (
      SELECT id FROM tts_project WHERE source_scenario_id IS NOT NULL
    )
  `);
  console.log(
    `Deleted ${deletedLines.count ?? 0} inert dialogue line copy(ies).`
  );

  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
