import type { GenerationRecord } from "./types";

export type GenerationClaim =
  | { type: "reclaim"; nowIso: string; staleBeforeIso: string }
  | { type: "cleanup"; nowIso: string; staleBeforeIso: string }
  | { type: "pending" }
  | { type: "ready" }
  | { type: "ready-unsaved" }
  | { type: "purging" }
  | { type: "not-purging" };

export function matchesGenerationClaim(
  row: GenerationRecord,
  claim: GenerationClaim,
): boolean {
  switch (claim.type) {
    case "reclaim":
      if (row.savedAt) return false;
      if (row.status === "failed") return true;
      if (
        row.status === "pending" &&
        Date.parse(row.updatedAt) <= Date.parse(claim.staleBeforeIso)
      ) {
        return true;
      }
      return (
        row.status === "ready" &&
        row.expiresAt != null &&
        Date.parse(row.expiresAt) <= Date.parse(claim.nowIso)
      );
    case "cleanup":
      if (row.savedAt) return false;
      if (row.status === "purging") return false;
      if (!row.expiresAt || Date.parse(row.expiresAt) > Date.parse(claim.nowIso)) {
        return false;
      }
      if (row.status === "ready" || row.status === "failed") return true;
      return (
        row.status === "pending" &&
        Date.parse(row.updatedAt) <= Date.parse(claim.staleBeforeIso)
      );
    case "pending":
      return row.status === "pending";
    case "ready":
      return row.status === "ready";
    case "ready-unsaved":
      return row.status === "ready" && row.savedAt == null;
    case "purging":
      return row.status === "purging";
    case "not-purging":
      return row.status !== "purging";
  }
}

export function hasObsoleteObjectKeys(row: Pick<GenerationRecord, "obsoleteObjectKeys">): boolean {
  return (row.obsoleteObjectKeys?.length ?? 0) > 0;
}

export function isCleanupCandidate(row: GenerationRecord, nowIso: string, staleBeforeIso: string): boolean {
  if (row.status === "purging") return true;
  if (hasObsoleteObjectKeys(row)) return true;
  return matchesGenerationClaim(row, {
    type: "cleanup",
    nowIso,
    staleBeforeIso,
  });
}
