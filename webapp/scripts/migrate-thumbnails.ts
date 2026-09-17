// Re-encodes existing collection/scenario thumbnails into full + 512 WebP
// variants and writes both URLs. Idempotent: skips rows that already have a
// .webp thumbnailUrl and a thumbnailSmallUrl. Old objects are left in place.
//
//   pnpm db:migrate-thumbnails

import { eq } from "drizzle-orm";
import { dialogueCollection, dialogueScenario } from "../lib/db/schema";
import { db } from "../lib/db/standalone-client";
import { publishThumbnail } from "../lib/images/thumbnail-variants";

function alreadyMigrated(
  thumbnailUrl: string | null,
  thumbnailSmallUrl: string | null
): boolean {
  return (
    !!thumbnailSmallUrl &&
    !!thumbnailUrl &&
    thumbnailUrl.toLowerCase().includes(".webp")
  );
}

async function fetchBytes(url: string): Promise<Buffer> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`GET ${url} failed with ${response.status}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

async function main() {
  const collections = await db.query.dialogueCollection.findMany();
  let collectionUpdated = 0;
  let collectionSkipped = 0;
  for (const collection of collections) {
    if (!collection.thumbnailUrl) {
      collectionSkipped += 1;
      continue;
    }
    if (alreadyMigrated(collection.thumbnailUrl, collection.thumbnailSmallUrl)) {
      collectionSkipped += 1;
      continue;
    }
    const published = await publishThumbnail(
      `dialogue/${collection.id}/thumbnail`,
      await fetchBytes(collection.thumbnailUrl)
    );
    await db
      .update(dialogueCollection)
      .set({
        thumbnailUrl: published.thumbnailUrl,
        thumbnailSmallUrl: published.thumbnailSmallUrl,
        updatedAt: new Date(),
      })
      .where(eq(dialogueCollection.id, collection.id));
    collectionUpdated += 1;
    console.log(`collection ${collection.id} → ${published.thumbnailSmallUrl}`);
  }

  const scenarios = await db.query.dialogueScenario.findMany();
  let scenarioUpdated = 0;
  let scenarioSkipped = 0;
  for (const scenario of scenarios) {
    if (!scenario.thumbnailUrl) {
      scenarioSkipped += 1;
      continue;
    }
    if (alreadyMigrated(scenario.thumbnailUrl, scenario.thumbnailSmallUrl)) {
      scenarioSkipped += 1;
      continue;
    }
    const slash = scenario.id.indexOf("/");
    const collectionId = slash >= 0 ? scenario.id.slice(0, slash) : scenario.collectionId;
    const slug = slash >= 0 ? scenario.id.slice(slash + 1) : scenario.id;
    const published = await publishThumbnail(
      `dialogue/${collectionId}/${slug}/thumbnail`,
      await fetchBytes(scenario.thumbnailUrl)
    );
    await db
      .update(dialogueScenario)
      .set({
        thumbnailUrl: published.thumbnailUrl,
        thumbnailSmallUrl: published.thumbnailSmallUrl,
        updatedAt: new Date(),
      })
      .where(eq(dialogueScenario.id, scenario.id));
    scenarioUpdated += 1;
    console.log(`scenario ${scenario.id} → ${published.thumbnailSmallUrl}`);
  }

  console.log(
    `Done. collections ${collectionUpdated} updated / ${collectionSkipped} skipped; ` +
      `scenarios ${scenarioUpdated} updated / ${scenarioSkipped} skipped.`
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
