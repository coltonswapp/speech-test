import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { grammarPoint } from "@/lib/db/schema";
import {
  GrammarGenerationError,
  generateGrammarPoint,
  type GoldExample,
} from "@/lib/content/grammar-generate";

const bodySchema = z.object({
  pointID: z.string().min(1),
  title: z.string().min(1),
  headlineEnglish: z.string().optional(),
  orderIndex: z.number().int(),
});

const GOLD_EXAMPLE_LIMIT = 5;

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const existing = await db.query.grammarPoint.findFirst({
    where: eq(grammarPoint.id, parsed.data.pointID),
    columns: { id: true },
  });
  if (existing) {
    return NextResponse.json(
      { error: `Point ${parsed.data.pointID} already exists` },
      { status: 409 }
    );
  }

  const approved = await db.query.grammarPoint.findMany({
    where: eq(grammarPoint.status, "approved"),
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

  try {
    const generated = await generateGrammarPoint(
      {
        pointID: parsed.data.pointID,
        title: parsed.data.title,
        headlineEnglish: parsed.data.headlineEnglish,
        orderIndex: parsed.data.orderIndex,
      },
      goldExamples
    );

    const point = generated.point;
    const [inserted] = await db
      .insert(grammarPoint)
      .values({
        id: point.id,
        orderIndex: point.orderIndex,
        title: point.title,
        headlineEnglish: point.headlineEnglish,
        blurb: point.blurb,
        forms: point.forms,
        formation: point.formation,
        formationExamples: point.formationExamples,
        usage: point.usage,
        usageLadders: point.usageLadders,
        relatedPointIds: point.relatedPointIDs,
        examples: point.examples,
        drills: point.drills,
        pattern: point.pattern,
        reading: point.reading,
        shortDefinition: point.shortDefinition,
        structure: point.structure,
        register: point.register,
        contrastDrills: point.contrastDrills,
        status: "draft",
      })
      .returning();

    return NextResponse.json({
      point: inserted,
      validationIssues: generated.validationIssues,
      attemptCount: generated.attemptCount,
    });
  } catch (error) {
    if (error instanceof GrammarGenerationError) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
    throw error;
  }
}
