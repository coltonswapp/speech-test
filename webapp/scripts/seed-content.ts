// One-time migration: content/n5/points/*.json + checkpoints.json (the Swift
// repo's on-disk grammar content) -> Postgres grammar_point/grammar_checkpoint
// tables. Run with: pnpm db:seed-content
//
// Idempotent — uses upsert on id, safe to re-run after editing source JSON.

import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { sql } from "drizzle-orm";
import { db } from "../lib/db/standalone-client";
import { grammarCheckpoint, grammarPoint } from "../lib/db/schema";

const CONTENT_ROOT = path.resolve(__dirname, "../../content/n5");

type SourcePoint = {
  id: string;
  orderIndex: number;
  title: string;
  headlineEnglish: string;
  blurb?: string;
  forms?: string[];
  formation?: unknown[];
  formationExamples?: string[];
  usage?: unknown[];
  usageLadders?: unknown[];
  relatedPointIDs?: string[];
  examples: unknown[];
  drills?: unknown[];
  pattern?: string;
  reading?: string;
  shortDefinition?: string;
  structure?: string;
  register?: string;
  contrastDrills?: unknown[];
  status?: string;
  reviewNotes?: string;
  _provenance?: unknown;
};

type SourceCheckpoints = {
  jlptLevel: number;
  checkpoints: Array<{
    id: string;
    orderIndex: number;
    title: string;
    subtitle?: string;
    pointIDs: string[];
  }>;
};

async function main() {
  const pointsDir = path.join(CONTENT_ROOT, "points");
  const files = (await readdir(pointsDir)).filter((f) => f.endsWith(".json"));
  console.log(`Found ${files.length} point files in ${pointsDir}`);

  let inserted = 0;
  for (const file of files) {
    const raw = await readFile(path.join(pointsDir, file), "utf-8");
    const point: SourcePoint = JSON.parse(raw);

    await db
      .insert(grammarPoint)
      .values({
        id: point.id,
        orderIndex: point.orderIndex,
        title: point.title,
        headlineEnglish: point.headlineEnglish,
        blurb: point.blurb ?? null,
        forms: point.forms ?? [],
        formation: point.formation ?? [],
        formationExamples: point.formationExamples ?? null,
        usage: point.usage ?? null,
        usageLadders: point.usageLadders ?? null,
        relatedPointIds: point.relatedPointIDs ?? [],
        examples: point.examples,
        drills: point.drills ?? [],
        pattern: point.pattern ?? null,
        reading: point.reading ?? null,
        shortDefinition: point.shortDefinition ?? null,
        structure: point.structure ?? null,
        register: point.register ?? null,
        contrastDrills: point.contrastDrills ?? null,
        status: point.status ?? "draft",
        reviewNotes: point.reviewNotes ?? null,
        provenance: point._provenance ?? null,
      })
      .onConflictDoUpdate({
        target: grammarPoint.id,
        set: {
          orderIndex: sql`excluded.order_index`,
          title: sql`excluded.title`,
          headlineEnglish: sql`excluded.headline_english`,
          blurb: sql`excluded.blurb`,
          forms: sql`excluded.forms`,
          formation: sql`excluded.formation`,
          formationExamples: sql`excluded.formation_examples`,
          usage: sql`excluded.usage`,
          usageLadders: sql`excluded.usage_ladders`,
          relatedPointIds: sql`excluded.related_point_ids`,
          examples: sql`excluded.examples`,
          drills: sql`excluded.drills`,
          pattern: sql`excluded.pattern`,
          reading: sql`excluded.reading`,
          shortDefinition: sql`excluded.short_definition`,
          structure: sql`excluded.structure`,
          register: sql`excluded.register`,
          contrastDrills: sql`excluded.contrast_drills`,
          status: sql`excluded.status`,
          reviewNotes: sql`excluded.review_notes`,
          provenance: sql`excluded.provenance`,
          updatedAt: new Date(),
        },
      });
    inserted++;
  }
  console.log(`Upserted ${inserted} grammar points.`);

  const checkpointsPath = path.join(CONTENT_ROOT, "checkpoints.json");
  const checkpointsRaw = await readFile(checkpointsPath, "utf-8");
  const checkpointsFile: SourceCheckpoints = JSON.parse(checkpointsRaw);

  let checkpointCount = 0;
  for (const cp of checkpointsFile.checkpoints) {
    await db
      .insert(grammarCheckpoint)
      .values({
        id: cp.id,
        orderIndex: cp.orderIndex,
        title: cp.title,
        subtitle: cp.subtitle ?? null,
        pointIds: cp.pointIDs,
      })
      .onConflictDoUpdate({
        target: grammarCheckpoint.id,
        set: {
          orderIndex: sql`excluded.order_index`,
          title: sql`excluded.title`,
          subtitle: sql`excluded.subtitle`,
          pointIds: sql`excluded.point_ids`,
        },
      });
    checkpointCount++;
  }
  console.log(`Upserted ${checkpointCount} checkpoints.`);

  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
