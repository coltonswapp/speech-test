// Apply an approved grammar-backfill mapping onto scene highlights.
// Run from webapp/:
//   pnpm dotenv -e .env.local -- tsx scripts/grammar-backfill-apply.ts --mapping ../grammar-backfill/mappings/<slug>.json
//   pnpm dotenv -e .env.local -- tsx scripts/grammar-backfill-apply.ts --mapping … --dry-run
//
// Does not invent Pattern catalog entries. Skips orphan/ambiguous rows.
// See ../grammar-backfill/DUMP.md and ../grammar-backfill/README.md.

import { readFile } from "node:fs/promises";
import path from "node:path";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "../lib/db/standalone-client";
import { dialogueScenario, teachingPattern } from "../lib/db/schema";
import {
  highlightsSchema,
  type DialogueHighlights,
  type GrammarPatternRef,
} from "../lib/dialogue/types";

const mappingItemSchema = z.object({
  label: z.string(),
  patternId: z.string().nullable(),
  sourceSpokenStart: z.number().int().nonnegative().nullable().optional(),
  sourceSpokenEnd: z.number().int().nonnegative().nullable().optional(),
  orphan: z.boolean().default(false),
  ambiguous: z.boolean().default(false),
  note: z.string().nullable().optional(),
});

const mappingSceneSchema = z.object({
  sceneId: z.string(),
  items: z.array(mappingItemSchema),
});

const mappingFileSchema = z.object({
  collectionId: z.string(),
  scenes: z.array(mappingSceneSchema),
});

function parseArgs(argv: string[]) {
  let mappingPath: string | undefined;
  let dryRun = false;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--dry-run") {
      dryRun = true;
      continue;
    }
    if (arg === "--mapping") {
      mappingPath = argv[++i];
      continue;
    }
    if (arg.startsWith("--mapping=")) {
      mappingPath = arg.slice("--mapping=".length);
      continue;
    }
  }
  if (!mappingPath) {
    throw new Error(
      "Usage: tsx scripts/grammar-backfill-apply.ts --mapping <path> [--dry-run]"
    );
  }
  return {
    mappingPath: path.resolve(process.cwd(), mappingPath),
    dryRun,
  };
}

function applyItemsToPatterns(
  existing: GrammarPatternRef[],
  items: z.infer<typeof mappingItemSchema>[],
  knownPatternIds: Set<string>
): {
  next: GrammarPatternRef[];
  applied: number;
  skipped: string[];
} {
  const skipped: string[] = [];
  if (items.length !== existing.length) {
    skipped.push(
      `item count ${items.length} != existing grammar count ${existing.length}`
    );
  }

  const count = Math.min(items.length, existing.length);
  const next = existing.map((pattern) => ({ ...pattern }));
  let applied = 0;

  for (let i = 0; i < count; i++) {
    const item = items[i];
    const current = next[i];
    const currentLabel = current.label?.trim() ?? "";
    if (item.label.trim() !== currentLabel) {
      skipped.push(
        `index ${i}: label mismatch mapping="${item.label}" scene="${currentLabel}"`
      );
      continue;
    }
    if (item.orphan || item.ambiguous) {
      skipped.push(
        `index ${i}: skipped (${item.orphan ? "orphan" : "ambiguous"})${
          item.note ? ` — ${item.note}` : ""
        }`
      );
      continue;
    }
    if (!item.patternId) {
      skipped.push(`index ${i}: missing patternId`);
      continue;
    }
    if (!knownPatternIds.has(item.patternId)) {
      skipped.push(
        `index ${i}: patternId "${item.patternId}" not in teaching_pattern`
      );
      continue;
    }
    if (
      item.sourceSpokenStart == null ||
      !Number.isInteger(item.sourceSpokenStart)
    ) {
      skipped.push(`index ${i}: missing sourceSpokenStart`);
      continue;
    }
    const start = item.sourceSpokenStart;
    const end =
      item.sourceSpokenEnd == null ? start : item.sourceSpokenEnd;
    if (end < start) {
      skipped.push(`index ${i}: sourceSpokenEnd < start`);
      continue;
    }
    next[i] = {
      ...current,
      label: currentLabel || item.label,
      patternId: item.patternId,
      sourceSpokenStart: start,
      sourceSpokenEnd: end,
    };
    applied += 1;
  }

  return { next, applied, skipped };
}

async function main() {
  const { mappingPath, dryRun } = parseArgs(process.argv.slice(2));
  const raw = await readFile(mappingPath, "utf8");
  const mapping = mappingFileSchema.parse(JSON.parse(raw));

  const patternRows = await db.query.teachingPattern.findMany({
    columns: { id: true },
  });
  const knownPatternIds = new Set(patternRows.map((row) => row.id));

  let totalApplied = 0;
  let totalScenes = 0;

  for (const scene of mapping.scenes) {
    totalScenes += 1;
    const row = await db.query.dialogueScenario.findFirst({
      where: eq(dialogueScenario.id, scene.sceneId),
    });
    if (!row) {
      console.warn(`Skip missing scene ${scene.sceneId}`);
      continue;
    }
    if (row.collectionId !== mapping.collectionId) {
      console.warn(
        `Skip ${scene.sceneId}: collectionId mismatch (db=${row.collectionId}, mapping=${mapping.collectionId})`
      );
      continue;
    }

    const parsed = highlightsSchema.safeParse(row.highlights);
    const highlights: DialogueHighlights = parsed.success
      ? parsed.data
      : { vocabulary: [], grammarPatterns: [], contextNotes: [] };
    const existing = highlights.grammarPatterns ?? [];

    const { next, applied, skipped } = applyItemsToPatterns(
      existing,
      scene.items,
      knownPatternIds
    );

    for (const reason of skipped) {
      console.warn(`  ${scene.sceneId}: ${reason}`);
    }

    if (applied === 0) {
      console.log(`${scene.sceneId}: nothing to apply`);
      continue;
    }

    const nextHighlights: DialogueHighlights = {
      vocabulary: highlights.vocabulary ?? [],
      contextNotes: highlights.contextNotes ?? [],
      grammarPatterns: next,
    };

    if (dryRun) {
      console.log(
        `${scene.sceneId}: would apply ${applied} item(s) (dry-run)`
      );
    } else {
      await db
        .update(dialogueScenario)
        .set({
          highlights: nextHighlights,
          updatedAt: new Date(),
        })
        .where(eq(dialogueScenario.id, scene.sceneId));
      console.log(`${scene.sceneId}: applied ${applied} item(s)`);
    }
    totalApplied += applied;
  }

  console.log(
    `${dryRun ? "Dry-run" : "Done"}: ${totalApplied} highlight(s) across ${totalScenes} scene(s) in ${mapping.collectionId}.`
  );
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
