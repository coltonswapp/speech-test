import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueCollection, dialogueScenario } from "@/lib/db/schema";
import {
  buildCollectionFile,
  serializeCollectionFile,
} from "@/lib/dialogue/export";
import { toExportableScenario } from "@/lib/dialogue/public-api";

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/content/dialogues/[collectionId]/export">
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

  const file = buildCollectionFile(collection, scenarios.map(toExportableScenario));

  return new NextResponse(serializeCollectionFile(file), {
    headers: {
      "Content-Type": "application/json",
      "Content-Disposition": `attachment; filename="${collection.id}.json"`,
    },
  });
}
