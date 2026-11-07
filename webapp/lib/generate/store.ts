import type { GenerationRecord } from "./types";
import {
  isCleanupCandidate,
  matchesGenerationClaim,
  type GenerationClaim,
} from "./claims";

export class DuplicateGenerationRequestError extends Error {
  readonly code = "23505";
  readonly constraint = "tts_generation_request_id_idx";
  constructor() {
    super("duplicate key value violates unique constraint \"tts_generation_request_id_idx\"");
    this.name = "DuplicateGenerationRequestError";
  }
}

export type GenerationStore = {
  insert(row: GenerationRecord): Promise<GenerationRecord>;
  get(id: string): Promise<GenerationRecord | null>;
  getByRequestId(requestId: string): Promise<GenerationRecord | null>;
  findRecentByHash(hash: string, sinceIso: string): Promise<GenerationRecord | null>;
  list(): Promise<GenerationRecord[]>;
  listCleanupCandidates(nowIso: string, staleBeforeIso: string, limit?: number): Promise<GenerationRecord[]>;
  compareAndUpdate(
    id: string,
    expectedRevision: number,
    claim: GenerationClaim,
    patch: Partial<Omit<GenerationRecord, "id" | "createdAt" | "revision">>,
  ): Promise<GenerationRecord | null>;
  deleteIfRevision(id: string, expectedRevision: number): Promise<GenerationRecord | null>;
};

export function memoryGenerationStore(
  seed: GenerationRecord[] = [],
): GenerationStore {
  const rows = new Map(seed.map((row) => [row.id, row]));
  return {
    async insert(row) {
      if (rows.has(row.id)) throw new Error("Duplicate generation id");
      if (
        row.requestId &&
        [...rows.values()].some((existing) => existing.requestId === row.requestId)
      ) {
        throw new DuplicateGenerationRequestError();
      }
      const stored = { ...row, revision: row.revision ?? 0 };
      rows.set(row.id, stored);
      return stored;
    },
    async get(id) {
      return rows.get(id) ?? null;
    },
    async getByRequestId(requestId) {
      return [...rows.values()].find((row) => row.requestId === requestId) ?? null;
    },
    async findRecentByHash(hash, sinceIso) {
      const since = Date.parse(sinceIso);
      return (
        [...rows.values()]
          .filter(
            (row) =>
              row.contentHash === hash && Date.parse(row.createdAt) >= since,
          )
          .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))[0] ??
        null
      );
    },
    async list() {
      return [...rows.values()].sort(
        (a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt),
      );
    },
    async listCleanupCandidates(nowIso, staleBeforeIso, limit = 100) {
      return [...rows.values()]
        .filter((row) => isCleanupCandidate(row, nowIso, staleBeforeIso))
        .sort((a, b) => Date.parse(a.expiresAt ?? "") - Date.parse(b.expiresAt ?? ""))
        .slice(0, limit);
    },
    async compareAndUpdate(id, expectedRevision, claim, patch) {
      const current = rows.get(id);
      if (!current) return null;
      if (current.revision !== expectedRevision) return null;
      if (!matchesGenerationClaim(current, claim)) return null;
      const next = {
        ...current,
        ...patch,
        id,
        createdAt: current.createdAt,
        revision: current.revision + 1,
      };
      rows.set(id, next);
      return next;
    },
    async deleteIfRevision(id, expectedRevision) {
      const current = rows.get(id);
      if (!current || current.revision !== expectedRevision) return null;
      rows.delete(id);
      return current;
    },
  };
}
