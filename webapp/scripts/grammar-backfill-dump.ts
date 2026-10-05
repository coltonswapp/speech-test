// Dump Pattern library + active collection grammar for backfill mapping.
// Run from webapp/:
//   pnpm dotenv -e .env.local -- tsx scripts/grammar-backfill-dump.ts
//
// Writes ../grammar-backfill/patterns.json and ../grammar-backfill/collections/<id>.json
// See ../grammar-backfill/DUMP.md.

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { asc, eq } from "drizzle-orm";
import { db } from "../lib/db/standalone-client";
import {
  dialogueCollection,
  dialogueScenario,
  teachingPattern,
} from "../lib/db/schema";
import { toExportedTeachingPattern } from "../lib/patterns/export";
import {
  highlightsSchema,
  spokenLinesOf,
  type DialogueLine,
} from "../lib/dialogue/types";

const ROOT = path.resolve(process.cwd(), "..", "grammar-backfill");
const COLLECTIONS_DIR = path.join(ROOT, "collections");

type DumpSpokenLine = {
  i: number;
  text: string;
  speaker: string;
};

type DumpGrammar = {
  label?: string;
  patternId?: string;
  sourceSpokenStart?: number;
  sourceSpokenEnd?: number;
};

type DumpScene = {
  sceneId: string;
  title: string;
  spokenLines: DumpSpokenLine[];
  grammar: DumpGrammar[];
};

type DumpCollection = {
  collectionId: string;
  scenes: DumpScene[];
};

function grammarForDump(highlights: unknown): DumpGrammar[] {
  const parsed = highlightsSchema.safeParse(highlights);
  if (!parsed.success) return [];
  return (parsed.data.grammarPatterns ?? []).map((pattern) => {
    const label = pattern.label?.trim();
    return {
      ...(label ? { label } : {}),
      ...(pattern.patternId ? { patternId: pattern.patternId } : {}),
      ...(pattern.sourceSpokenStart !== undefined
        ? { sourceSpokenStart: pattern.sourceSpokenStart }
        : {}),
      ...(pattern.sourceSpokenEnd !== undefined
        ? { sourceSpokenEnd: pattern.sourceSpokenEnd }
        : {}),
    };
  });
}

function spokenDump(lines: unknown): DumpSpokenLine[] {
  if (!Array.isArray(lines)) return [];
  const spoken = spokenLinesOf(lines as DialogueLine[]);
  return spoken.map((line, i) => ({
    i,
    text: line.japanese,
    speaker: line.speaker,
  }));
}

async function main() {
  await mkdir(COLLECTIONS_DIR, { recursive: true });

  const patterns = await db.query.teachingPattern.findMany({
    orderBy: [asc(teachingPattern.orderIndex), asc(teachingPattern.id)],
  });
  const patternsJson = patterns.map((row) => toExportedTeachingPattern(row));
  await writeFile(
    path.join(ROOT, "patterns.json"),
    `${JSON.stringify(patternsJson, null, 2)}\n`,
    "utf8"
  );
  console.log(`Wrote patterns.json (${patternsJson.length} patterns)`);

  const collections = await db.query.dialogueCollection.findMany({
    where: eq(dialogueCollection.isActive, true),
    orderBy: [asc(dialogueCollection.orderIndex), asc(dialogueCollection.id)],
  });

  let sceneCount = 0;
  for (const collection of collections) {
    const scenarios = await db.query.dialogueScenario.findMany({
      where: eq(dialogueScenario.collectionId, collection.id),
      orderBy: [asc(dialogueScenario.orderIndex)],
    });

    const dump: DumpCollection = {
      collectionId: collection.id,
      scenes: scenarios.map((scenario) => {
        sceneCount += 1;
        return {
          sceneId: scenario.id,
          title: scenario.menuTitle,
          spokenLines: spokenDump(scenario.lines),
          grammar: grammarForDump(scenario.highlights),
        };
      }),
    };

    const outPath = path.join(COLLECTIONS_DIR, `${collection.id}.json`);
    await writeFile(outPath, `${JSON.stringify(dump, null, 2)}\n`, "utf8");
    console.log(
      `Wrote collections/${collection.id}.json (${dump.scenes.length} scenes)`
    );
  }

  console.log(
    `Done. ${collections.length} active collection(s), ${sceneCount} scene(s).`
  );
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
