import type { PostgresJsDatabase } from "drizzle-orm/postgres-js";
import { eq, sql } from "drizzle-orm";
import type * as schema from "@/lib/db/schema";
import { dialogueCollection, dialogueScenario } from "@/lib/db/schema";
import { collectionFileSchema, type CollectionFile } from "@/lib/dialogue/types";

// Lossless import of a shizen collection file into the dialogue tables.
// Shared by the import API route and scripts/seed-dialogues.ts (which uses the
// standalone client), so the db handle is a parameter.

type Db = PostgresJsDatabase<typeof schema>;

export function parseCollectionFile(raw: string): CollectionFile {
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    throw new Error("File is not valid JSON.");
  }
  const parsed = collectionFileSchema.safeParse(json);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .slice(0, 5)
      .map((issue) => `${issue.path.join(".")}: ${issue.message}`)
      .join("; ");
    throw new Error(`Not a valid dialogue collection file: ${issues}`);
  }
  return parsed.data;
}

export async function upsertCollectionFile(
  db: Db,
  file: CollectionFile
): Promise<{ collectionId: string; scenarioCount: number }> {
  await db
    .insert(dialogueCollection)
    .values({
      id: file.id,
      title: file.title,
      subtitle: file.subtitle ?? null,
      sceneImage: file.sceneImage ?? null,
      thumbnailUrl: file.thumbnailUrl ?? null,
    })
    .onConflictDoUpdate({
      target: dialogueCollection.id,
      set: {
        title: sql`excluded.title`,
        subtitle: sql`excluded.subtitle`,
        sceneImage: sql`excluded.scene_image`,
        thumbnailUrl: sql`excluded.thumbnail_url`,
        updatedAt: new Date(),
      },
    });

  await db
    .delete(dialogueScenario)
    .where(eq(dialogueScenario.collectionId, file.id));

  if (file.scenarios.length > 0) {
    await db.insert(dialogueScenario).values(
      file.scenarios.map((scenario, index) => ({
        id: scenario.id,
        collectionId: file.id,
        orderIndex: index,
        menuTitle: scenario.menuTitle,
        menuSubtitle: scenario.menuSubtitle ?? null,
        japanese: scenario.japanese,
        romaji: scenario.romaji,
        english: scenario.english,
        targetSubstring: scenario.targetSubstring ?? null,
        audioKey: scenario.audioKey ?? null,
        grammarPointIds: scenario.grammarPointIDs ?? [],
        setting: scenario.scenario.setting ?? null,
        thumbnailUrl: scenario.thumbnailUrl ?? null,
        lines: scenario.scenario.lines,
        highlights: scenario.highlights ?? null,
        quiz: scenario.quiz ?? null,
        tokenSync: scenario.tokenSync ?? null,
      }))
    );
  }

  return { collectionId: file.id, scenarioCount: file.scenarios.length };
}
