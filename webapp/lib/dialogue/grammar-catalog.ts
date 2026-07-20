import "server-only";

import { db } from "@/lib/db/client";

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

export async function fetchGrammarPointContext(): Promise<
  GrammarPointContext[]
> {
  return db.query.grammarPoint.findMany({
    columns: contextColumns,
  });
}

export async function fetchGrammarPointIdSet(): Promise<Set<string>> {
  const points = await db.query.grammarPoint.findMany({
    columns: { id: true },
  });
  return new Set(points.map((point) => point.id));
}

export function filterGrammarPointIds(
  ids: string[] | undefined,
  known: Set<string>
): string[] | undefined {
  if (!ids) return undefined;
  const filtered = ids.filter((id) => known.has(id));
  return filtered.length > 0 ? filtered : undefined;
}

export function filterGrammarPointIdsRequired(
  ids: string[],
  known: Set<string>
): string[] {
  return ids.filter((id) => known.has(id));
}
