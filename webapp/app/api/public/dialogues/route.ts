import { NextResponse } from "next/server";
import {
  listPublicCurriculumUnits,
  listPublicDialogueCollections,
} from "@/lib/dialogue/public-api";

export async function GET() {
  const [units, collections] = await Promise.all([
    listPublicCurriculumUnits(),
    listPublicDialogueCollections(),
  ]);
  return NextResponse.json(
    { units, collections },
    {
      headers: {
        "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300",
      },
    }
  );
}
