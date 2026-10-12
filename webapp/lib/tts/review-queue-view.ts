/**
 * Pure view helpers for the Studio review queue.
 * No schema — derived from existing take / sibling fields.
 */

export const REVIEW_JLPT_TRACKS = [
  { level: 5, label: "N5" },
  { level: 4, label: "N4" },
  { level: 3, label: "N3" },
] as const;

export type ReviewJlptTrackLevel = (typeof REVIEW_JLPT_TRACKS)[number]["level"];

export function parseReviewJlptTrack(
  raw: string | number | null | undefined,
): ReviewJlptTrackLevel {
  const n = typeof raw === "number" ? raw : Number(raw);
  if (n === 5 || n === 4 || n === 3) return n;
  return 5;
}

/** Curriculum N5/N4/N3 tracks. Unfiled and other levels land on N5. */
export function reviewQueueTrack(
  jlptLevel: number | null | undefined,
): ReviewJlptTrackLevel {
  if (jlptLevel === 4) return 4;
  if (jlptLevel === 3) return 3;
  return 5;
}

export function sceneKeyForTake(take: {
  scenarioId: string | null;
  projectId: string;
}): string {
  return take.scenarioId ?? `project:${take.projectId}`;
}

export type TakeSibling = {
  variantId: string;
  createdAt: string;
  takeIndex: number;
  isPublishedTake: boolean;
  isSelectedTake: boolean;
};

export function newerTakesThan<T extends TakeSibling>(
  take: { variantId: string; createdAt: string; siblings: T[] },
): T[] {
  return take.siblings
    .filter(
      (sib) =>
        sib.variantId !== take.variantId && sib.createdAt > take.createdAt,
    )
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

export function takeIsSuperseded(take: {
  variantId: string;
  createdAt: string;
  siblings: TakeSibling[];
}): boolean {
  return newerTakesThan(take).length > 0;
}

/** Newest queued take per scene (project/scenario). */
export function latestQueuedTakeIds<
  T extends {
    variantId: string;
    projectId: string;
    scenarioId: string | null;
    createdAt: string;
  },
>(takes: T[]): Set<string> {
  const latest = new Map<string, T>();
  for (const take of takes) {
    const key = sceneKeyForTake(take);
    const existing = latest.get(key);
    if (!existing || take.createdAt > existing.createdAt) {
      latest.set(key, take);
    }
  }
  return new Set([...latest.values()].map((take) => take.variantId));
}

export type GateAButtonKind = "publish" | "republish" | "published";

export type GateAButtonState = {
  kind: GateAButtonKind;
  publishedAt: string | null;
};

function scenePublishedVariantId(take: {
  variantId: string;
  isPublishedTake: boolean;
  siblings: Array<{ variantId: string; isPublishedTake: boolean }>;
}): string | null {
  if (take.isPublishedTake) return take.variantId;
  return take.siblings.find((sib) => sib.isPublishedTake)?.variantId ?? null;
}

function sceneSelectedVariantId(take: {
  variantId: string;
  isSelectedTake: boolean;
  siblings: Array<{ variantId: string; isSelectedTake: boolean }>;
}): string | null {
  if (take.isSelectedTake) return take.variantId;
  return take.siblings.find((sib) => sib.isSelectedTake)?.variantId ?? null;
}

/**
 * Gate A button on a review card:
 * - Published (disabled) when the scene's selected take is already the published one
 * - Republish when a published take exists but the selected take differs
 * - Publish to database when nothing has landed yet
 */
export function gateAButtonState(take: {
  variantId: string;
  isPublishedTake: boolean;
  isSelectedTake: boolean;
  siblings: Array<{
    variantId: string;
    isPublishedTake: boolean;
    isSelectedTake: boolean;
  }>;
  timing?: { publishedAt?: string } | null;
  scenarioPublishedAt?: string | null;
}): GateAButtonState {
  const publishedId = scenePublishedVariantId(take);
  const selectedId = sceneSelectedVariantId(take);
  const publishedAt =
    take.timing?.publishedAt ?? take.scenarioPublishedAt ?? null;
  if (publishedId && selectedId && publishedId === selectedId) {
    return { kind: "published", publishedAt };
  }
  if (publishedId) return { kind: "republish", publishedAt };
  return { kind: "publish", publishedAt: null };
}

export function countTakesByTrack<
  T extends { jlptLevel: number | null },
>(takes: T[]): Record<ReviewJlptTrackLevel, number> {
  const counts: Record<ReviewJlptTrackLevel, number> = { 5: 0, 4: 0, 3: 0 };
  for (const take of takes) {
    counts[reviewQueueTrack(take.jlptLevel)] += 1;
  }
  return counts;
}
