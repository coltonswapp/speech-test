import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { desc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsExport } from "@/lib/db/schema";

export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/tts/projects/[id]/variants/[variantId]/exports">
) {
  const { variantId } = await ctx.params;
  const exports = await db.query.ttsExport.findMany({
    where: eq(ttsExport.variantId, variantId),
    orderBy: [desc(ttsExport.createdAt)],
  });
  return NextResponse.json({ exports });
}
