import type { GenerationRecord } from "./types";

export type GenerationStore = {
  insert(row: GenerationRecord): Promise<GenerationRecord>;
  update(
    id: string,
    patch: Partial<Omit<GenerationRecord, "id" | "createdAt">>,
  ): Promise<GenerationRecord | null>;
  get(id: string): Promise<GenerationRecord | null>;
  getByRequestId(requestId: string): Promise<GenerationRecord | null>;
  findRecentByHash(hash: string, sinceIso: string): Promise<GenerationRecord | null>;
  list(): Promise<GenerationRecord[]>;
  delete(id: string): Promise<GenerationRecord | null>;
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
        throw new Error("Duplicate request id");
      }
      rows.set(row.id, row);
      return row;
    },
    async update(id, patch) {
      const current = rows.get(id);
      if (!current) return null;
      const next = { ...current, ...patch, id, createdAt: current.createdAt };
      rows.set(id, next);
      return next;
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
    async delete(id) {
      const current = rows.get(id);
      if (!current) return null;
      rows.delete(id);
      return current;
    },
  };
}
