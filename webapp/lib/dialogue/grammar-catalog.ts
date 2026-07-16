import "server-only";

import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { grammarPoint } from "@/lib/db/schema";

export type GrammarPointContext = {
  id: string;
  title: string;
  pattern: string | null;
  shortDefinition: string | null;
};

const contextColumns = {
  id: true,
  title: true,
  pattern: true,
  shortDefinition: true,
} as const;

export async function fetchApprovedGrammarPointContext(): Promise<
  GrammarPointContext[]
> {
  return db.query.grammarPoint.findMany({
    where: eq(grammarPoint.status, "approved"),
    columns: contextColumns,
  });
}

export async function fetchApprovedGrammarPointIdSet(): Promise<Set<string>> {
  const points = await db.query.grammarPoint.findMany({
    where: eq(grammarPoint.status, "approved"),
    columns: { id: true },
  });
  return new Set(points.map((point) => point.id));
}

export function filterGrammarPointIds(
  ids: string[] | undefined,
  approved: Set<string>
): string[] | undefined {
  if (!ids) return undefined;
  const filtered = ids.filter((id) => approved.has(id));
  return filtered.length > 0 ? filtered : undefined;
}

export function filterGrammarPointIdsRequired(
  ids: string[],
  approved: Set<string>
): string[] {
  return ids.filter((id) => approved.has(id));
}
