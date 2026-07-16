import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { eq, and, ne } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { grammarPoint } from "@/lib/db/schema";
import {
  GrammarGenerationError,
  regenerateSection,
  type GoldExample,
  type SectionTask,
} from "@/lib/content/grammar-generate";
import type { GrammarPointInput } from "@/lib/content/types";

const bodySchema = z.object({
  task: z.enum(["overview", "formation", "usage", "usageLadders", "example", "drills"]),
  customInstructions: z.string().optional(),
});

const GOLD_EXAMPLE_LIMIT = 5;

export async function POST(
  request: NextRequest,
  ctx: RouteContext<"/api/content/points/[id]/regenerate-section">
) {
  const { id } = await ctx.params;
  const body = await request.json();
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const point = await db.query.grammarPoint.findFirst({
    where: eq(grammarPoint.id, id),
  });
  if (!point) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const approved = await db.query.grammarPoint.findMany({
    where: and(eq(grammarPoint.status, "approved"), ne(grammarPoint.id, id)),
    limit: GOLD_EXAMPLE_LIMIT,
  });
  const goldExamples: GoldExample[] = approved.map((p) => ({
    id: p.id,
    orderIndex: p.orderIndex,
    title: p.title,
    headlineEnglish: p.headlineEnglish,
    blurb: p.blurb,
    forms: p.forms,
    formation: p.formation as GoldExample["formation"],
    usage: p.usage as GoldExample["usage"],
    usageLadders: p.usageLadders as GoldExample["usageLadders"],
    relatedPointIDs: p.relatedPointIds,
    examples: p.examples as GoldExample["examples"],
    pattern: p.pattern,
    reading: p.reading,
    shortDefinition: p.shortDefinition,
    structure: p.structure,
    register: p.register as GoldExample["register"],
    contrastDrills: p.contrastDrills as GoldExample["contrastDrills"],
  }));

  const context: GrammarPointInput = {
    id: point.id,
    orderIndex: point.orderIndex,
    title: point.title,
    headlineEnglish: point.headlineEnglish,
    blurb: point.blurb,
    forms: point.forms,
    formation: point.formation as GrammarPointInput["formation"],
    formationExamples: point.formationExamples,
    usage: point.usage as GrammarPointInput["usage"],
    usageLadders: point.usageLadders as GrammarPointInput["usageLadders"],
    relatedPointIDs: point.relatedPointIds,
    examples: point.examples as GrammarPointInput["examples"],
    drills: point.drills as GrammarPointInput["drills"],
    pattern: point.pattern,
    reading: point.reading,
    shortDefinition: point.shortDefinition,
    structure: point.structure,
    register: point.register as GrammarPointInput["register"],
    contrastDrills: point.contrastDrills as GrammarPointInput["contrastDrills"],
    status: point.status as GrammarPointInput["status"],
    reviewNotes: point.reviewNotes,
  };

  try {
    const { point: merged } = await regenerateSection(
      parsed.data.task as SectionTask,
      context,
      goldExamples,
      parsed.data.customInstructions
    );

    const [updated] = await db
      .update(grammarPoint)
      .set({
        headlineEnglish: merged.headlineEnglish,
        blurb: merged.blurb,
        forms: merged.forms,
        formation: merged.formation,
        usage: merged.usage,
        usageLadders: merged.usageLadders,
        examples: merged.examples,
        drills: merged.drills,
        updatedAt: new Date(),
      })
      .where(eq(grammarPoint.id, id))
      .returning();

    return NextResponse.json({ point: updated });
  } catch (error) {
    if (error instanceof GrammarGenerationError) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
    throw error;
  }
}
