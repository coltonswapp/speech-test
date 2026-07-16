import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { asc, eq, ilike, or, type SQL } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { grammarPoint } from "@/lib/db/schema";

export async function GET(request: NextRequest) {
  const status = request.nextUrl.searchParams.get("status");
  const search = request.nextUrl.searchParams.get("search")?.trim();

  const conditions: SQL[] = [];
  if (status) {
    conditions.push(eq(grammarPoint.status, status));
  }
  if (search) {
    const pattern = `%${search}%`;
    const searchCondition = or(
      ilike(grammarPoint.title, pattern),
      ilike(grammarPoint.id, pattern),
      ilike(grammarPoint.headlineEnglish, pattern)
    );
    if (searchCondition) conditions.push(searchCondition);
  }

  const points = await db.query.grammarPoint.findMany({
    where: conditions.length > 0 ? (table, { and }) => and(...conditions) : undefined,
    orderBy: [asc(grammarPoint.orderIndex)],
    columns: {
      id: true,
      orderIndex: true,
      title: true,
      headlineEnglish: true,
      pattern: true,
      status: true,
      updatedAt: true,
    },
  });

  return NextResponse.json({ points });
}
