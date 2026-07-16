// Seeds shizen/Resources/Dialogue/*.json (dialogue collection files) into the
// dialogue_collection/dialogue_scenario tables. Run with: pnpm db:seed-dialogues
//
// Idempotent — upserts the collection and replaces its scenarios, safe to
// re-run after editing source JSON.

import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { db } from "../lib/db/standalone-client";
import { parseCollectionFile, upsertCollectionFile } from "../lib/dialogue/import";

const DIALOGUE_ROOT = path.resolve(__dirname, "../../shizen/Resources/Dialogue");

async function main() {
  const files = (await readdir(DIALOGUE_ROOT)).filter((f) =>
    f.endsWith(".json")
  );
  console.log(`Found ${files.length} collection files in ${DIALOGUE_ROOT}`);

  for (const file of files) {
    const raw = await readFile(path.join(DIALOGUE_ROOT, file), "utf-8");
    const parsed = parseCollectionFile(raw);
    const { collectionId, scenarioCount } = await upsertCollectionFile(
      db,
      parsed
    );
    console.log(`Upserted "${collectionId}" (${scenarioCount} scenarios).`);
  }

  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
