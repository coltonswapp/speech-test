import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, inArray } from "drizzle-orm";
import { db } from "@/lib/db/client";
import {
  dialogueCollection,
  dialogueScenario,
  ttsProject,
  ttsVariant,
} from "@/lib/db/schema";
import { createCollectionSchema, type DialogueLine } from "@/lib/dialogue/types";
import { buildScenarioReadiness } from "@/lib/dialogue/scenario-readiness";
import { conversationContentHash } from "@/lib/tts/content-hash";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";

export async function GET() {
  const [collections, scenarios] = await Promise.all([
    db.query.dialogueCollection.findMany({
      orderBy: [asc(dialogueCollection.orderIndex), asc(dialogueCollection.id)],
    }),
    db.query.dialogueScenario.findMany({
      orderBy: [asc(dialogueScenario.orderIndex)],
      columns: {
        id: true,
        collectionId: true,
        orderIndex: true,
        menuTitle: true,
        menuSubtitle: true,
        audioKey: true,
        publishedAudioUrl: true,
        publishedVariantId: true,
        publishedContentHash: true,
        publishedAt: true,
        updatedAt: true,
        lines: true,
        quiz: true,
        tokenSync: true,
      },
    }),
  ]);

  const scenarioIds = scenarios.map((s) => s.id);
  const projects =
    scenarioIds.length > 0
      ? await db.query.ttsProject.findMany({
          where: inArray(ttsProject.sourceScenarioId, scenarioIds),
          columns: {
            sourceScenarioId: true,
            selectedVariantId: true,
          },
        })
      : [];
  const projectByScenarioId = new Map(
    projects.map((p) => [p.sourceScenarioId, p]),
  );

  const variantIds = new Set<string>();
  for (const scenario of scenarios) {
    if (scenario.publishedVariantId) {
      variantIds.add(scenario.publishedVariantId);
    }
    const selected = projectByScenarioId.get(scenario.id)?.selectedVariantId;
    if (selected) variantIds.add(selected);
  }

  const variants =
    variantIds.size > 0
      ? await db.query.ttsVariant.findMany({
          where: inArray(ttsVariant.id, [...variantIds]),
          columns: {
            id: true,
            dialogueLineSwitchSamples: true,
            tokenSync: true,
            contentHash: true,
          },
        })
      : [];
  const variantById = new Map(variants.map((v) => [v.id, v]));

  const byCollection = new Map<
    string,
    Array<ReturnType<typeof summarizeScenario>>
  >();

  function summarizeScenario(scenario: (typeof scenarios)[number]) {
    const publishedVariant = scenario.publishedVariantId
      ? variantById.get(scenario.publishedVariantId)
      : undefined;
    const selectedVariantId = projectByScenarioId.get(
      scenario.id,
    )?.selectedVariantId;
    const selectedVariant = selectedVariantId
      ? variantById.get(selectedVariantId)
      : undefined;
    // Prefer the published take's line marks; fall back to the selected take
    // so drafts still show timing progress.
    const timingVariant = publishedVariant ?? selectedVariant;
    const workingSyncVariant = publishedVariant ?? selectedVariant;
    const spokenLines = scenarioLinesToConversation(
      scenario.lines as DialogueLine[],
    ).lines;
    const contentHash = conversationContentHash(spokenLines);
    const readiness = buildScenarioReadiness({
      publishedAudioUrl: scenario.publishedAudioUrl,
      lines: scenario.lines,
      quiz: scenario.quiz,
      tokenSync: scenario.tokenSync,
      markSamples: timingVariant?.dialogueLineSwitchSamples,
      workingTokenSync: workingSyncVariant?.tokenSync,
      contentHash,
    });

    return {
      id: scenario.id,
      collectionId: scenario.collectionId,
      orderIndex: scenario.orderIndex,
      menuTitle: scenario.menuTitle,
      menuSubtitle: scenario.menuSubtitle,
      audioKey: scenario.audioKey,
      publishedAudioUrl: scenario.publishedAudioUrl,
      publishedVariantId: scenario.publishedVariantId,
      publishedContentHash: scenario.publishedContentHash,
      publishedAt: scenario.publishedAt,
      updatedAt: scenario.updatedAt,
      readiness,
    };
  }

  for (const scenario of scenarios) {
    const summary = summarizeScenario(scenario);
    const list = byCollection.get(scenario.collectionId) ?? [];
    list.push(summary);
    byCollection.set(scenario.collectionId, list);
  }

  return NextResponse.json({
    collections: collections.map((collection) => ({
      ...collection,
      scenarios: byCollection.get(collection.id) ?? [],
    })),
  });
}

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = createCollectionSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const existing = await db.query.dialogueCollection.findFirst({
    where: (table, { eq }) => eq(table.id, parsed.data.id),
  });
  if (existing) {
    return NextResponse.json(
      { error: `Collection "${parsed.data.id}" already exists.` },
      { status: 409 },
    );
  }

  const [collection] = await db
    .insert(dialogueCollection)
    .values({
      id: parsed.data.id,
      title: parsed.data.title,
      subtitle: parsed.data.subtitle ?? null,
      sceneImage: parsed.data.sceneImage ?? null,
      unitId: parsed.data.unitId ?? null,
    })
    .returning();

  return NextResponse.json({ collection }, { status: 201 });
}
