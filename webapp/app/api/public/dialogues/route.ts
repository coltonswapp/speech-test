import { NextResponse } from "next/server";
import { listPublicDialogueCollections } from "@/lib/dialogue/public-api";

export async function GET() {
  const collections = await listPublicDialogueCollections();
  return NextResponse.json(
    { collections },
    {
      headers: {
        "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300",
      },
    }
  );
}
