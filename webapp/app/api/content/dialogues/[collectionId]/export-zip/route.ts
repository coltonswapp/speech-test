import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, eq, inArray } from "drizzle-orm";
import JSZip from "jszip";
import { db } from "@/lib/db/client";
import { dialogueCollection, dialogueScenario, ttsProject, ttsVariant } from "@/lib/db/schema";
import {
  buildCollectionFile,
  serializeCollectionFile,
  type ExportableScenario,
} from "@/lib/dialogue/export";
import { toExportableScenario } from "@/lib/dialogue/public-api";
import { renderVariantM4a } from "@/lib/tts/variant-audio";

// One-stop export: the shizen collection JSON plus each scenario's selected
// take rendered as m4a. Scenarios with a selected take get audioKey set to
// their full id, matching shizen's Dialogue/Audio/<collectionId>/<slug>.m4a
// bundle lookup; scenarios without audio keep audioKey empty (on-device TTS).

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/export-zip">
) {
  const { collectionId } = await ctx.params;

  const collection = await db.query.dialogueCollection.findFirst({
    where: eq(dialogueCollection.id, collectionId),
  });
  if (!collection) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const scenarios = await db.query.dialogueScenario.findMany({
    where: eq(dialogueScenario.collectionId, collectionId),
    orderBy: [asc(dialogueScenario.orderIndex)],
  });

  const projects = scenarios.length
    ? await db.query.ttsProject.findMany({
        where: inArray(
          ttsProject.sourceScenarioId,
          scenarios.map((s) => s.id)
        ),
      })
    : [];
  const selectedVariantIds = projects
    .map((p) => p.selectedVariantId)
    .filter((id): id is string => !!id);
  const variants = selectedVariantIds.length
    ? await db.query.ttsVariant.findMany({
        where: inArray(ttsVariant.id, selectedVariantIds),
      })
    : [];
  const variantById = new Map(variants.map((v) => [v.id, v]));
  const projectByScenarioId = new Map(
    projects.map((p) => [p.sourceScenarioId, p])
  );

  const zip = new JSZip();
  const exportScenarios: ExportableScenario[] = [];
  for (const scenario of scenarios) {
    const project = projectByScenarioId.get(scenario.id);
    // A dangling selectedVariantId (take deleted) counts as no take.
    const variant = project?.selectedVariantId
      ? variantById.get(project.selectedVariantId)
      : undefined;
    if (!variant) {
      exportScenarios.push(toExportableScenario(scenario));
      continue;
    }
    const m4a = await renderVariantM4a(variant);
    zip.file(`Audio/${scenario.id}.m4a`, m4a);
    exportScenarios.push({ ...toExportableScenario(scenario), audioKey: scenario.id });
  }

  const file = buildCollectionFile(collection, exportScenarios);
  zip.file(`${collection.id}.json`, serializeCollectionFile(file));

  const buffer = await zip.generateAsync({ type: "nodebuffer" });
  return new NextResponse(new Uint8Array(buffer), {
    headers: {
      "Content-Type": "application/zip",
      "Content-Disposition": `attachment; filename="${collection.id}.zip"`,
    },
  });
}
