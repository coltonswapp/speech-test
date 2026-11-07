import "server-only";
import { desc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsGeneration } from "@/lib/db/schema";
import { variantTokenSyncSchema } from "@/lib/dialogue/types";
import { generateLineInputSchema, generateLineTimingSchema } from "./types";
import type { GenerationRecord } from "./types";
import type { GenerationStore } from "./store";

function iso(value: Date | string | null | undefined): string | null {
  if (!value) return null;
  return value instanceof Date ? value.toISOString() : value;
}

function fromRow(row: typeof ttsGeneration.$inferSelect): GenerationRecord {
  const lines = generateLineInputSchema.array().parse(row.lines);
  const lineTimings = row.lineTimings
    ? generateLineTimingSchema.array().parse(row.lineTimings)
    : null;
  const tokenSync = row.tokenSync
    ? (variantTokenSyncSchema.parse(row.tokenSync) as GenerationRecord["tokenSync"])
    : null;
  return {
    id: row.id,
    createdAt: iso(row.createdAt) ?? new Date().toISOString(),
    updatedAt: iso(row.updatedAt) ?? new Date().toISOString(),
    savedAt: iso(row.savedAt),
    title: row.title,
    kind: row.kind === "upload" ? "upload" : "tts",
    model: row.model,
    requestId: row.requestId,
    contentHash: row.contentHash,
    lines,
    lineTimings,
    tokenSync,
    transcript: row.transcript,
    wavObjectKey: row.wavObjectKey,
    mp3ObjectKey: row.mp3ObjectKey,
    sampleRate: row.sampleRate,
    durationSeconds: row.durationSeconds,
    byteCount: row.byteCount,
  };
}

function toColumns(row: Omit<GenerationRecord, "id"> & { id?: string }) {
  return {
    title: row.title,
    kind: row.kind,
    model: row.model,
    requestId: row.requestId,
    contentHash: row.contentHash,
    lines: row.lines,
    lineTimings: row.lineTimings,
    tokenSync: row.tokenSync,
    transcript: row.transcript,
    wavObjectKey: row.wavObjectKey,
    mp3ObjectKey: row.mp3ObjectKey,
    sampleRate: row.sampleRate,
    durationSeconds: row.durationSeconds,
    byteCount: row.byteCount,
    savedAt: row.savedAt ? new Date(row.savedAt) : null,
    updatedAt: new Date(row.updatedAt),
  };
}

export const drizzleGenerationStore: GenerationStore = {
  async insert(row) {
    const [created] = await db
      .insert(ttsGeneration)
      .values({
        id: row.id,
        createdAt: new Date(row.createdAt),
        ...toColumns(row),
      })
      .returning();
    return fromRow(created);
  },
  async update(id, patch) {
    const current = await this.get(id);
    if (!current) return null;
    const next = { ...current, ...patch, id, createdAt: current.createdAt };
    const [updated] = await db
      .update(ttsGeneration)
      .set(toColumns(next))
      .where(eq(ttsGeneration.id, id))
      .returning();
    return updated ? fromRow(updated) : null;
  },
  async get(id) {
    const row = await db.query.ttsGeneration.findFirst({
      where: eq(ttsGeneration.id, id),
    });
    return row ? fromRow(row) : null;
  },
  async getByRequestId(requestId) {
    const row = await db.query.ttsGeneration.findFirst({
      where: eq(ttsGeneration.requestId, requestId),
    });
    return row ? fromRow(row) : null;
  },
  async findRecentByHash(hash, sinceIso) {
    const rows = await db.query.ttsGeneration.findMany({
      where: eq(ttsGeneration.contentHash, hash),
      orderBy: [desc(ttsGeneration.createdAt)],
      limit: 8,
    });
    const since = Date.parse(sinceIso);
    const match = rows.find((row) => row.createdAt.getTime() >= since);
    return match ? fromRow(match) : null;
  },
  async list() {
    const rows = await db.query.ttsGeneration.findMany({
      orderBy: [desc(ttsGeneration.createdAt)],
    });
    return rows.map(fromRow);
  },
  async delete(id) {
    const [deleted] = await db
      .delete(ttsGeneration)
      .where(eq(ttsGeneration.id, id))
      .returning();
    return deleted ? fromRow(deleted) : null;
  },
};
