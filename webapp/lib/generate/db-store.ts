import "server-only";
import { and, desc, eq, inArray, isNull, lte, ne, or, sql } from "drizzle-orm";
import type { SQL } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { ttsGeneration } from "@/lib/db/schema";
import { variantTokenSyncSchema } from "@/lib/dialogue/types";
import { generateLineInputSchema, generateLineTimingSchema } from "./types";
import type { GenerationRecord, GenerationStatus } from "./types";
import type { GenerationClaim } from "./claims";
import type { GenerationStore } from "./store";

function iso(value: Date | string | null | undefined): string | null {
  if (!value) return null;
  return value instanceof Date ? value.toISOString() : value;
}

function parseStatus(value: string | null | undefined): GenerationStatus {
  if (value === "pending" || value === "failed" || value === "purging") return value;
  return "ready";
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
    expiresAt: iso(row.expiresAt),
    status: parseStatus(row.status),
    revision: row.revision ?? 0,
    error: row.error,
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
    obsoleteObjectKeys: Array.isArray(row.obsoleteObjectKeys)
      ? row.obsoleteObjectKeys.filter((key): key is string => typeof key === "string")
      : [],
    sampleRate: row.sampleRate,
    durationSeconds: row.durationSeconds,
    byteCount: row.byteCount,
  };
}

function toInsertColumns(row: Omit<GenerationRecord, "id"> & { id?: string }) {
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
    obsoleteObjectKeys: row.obsoleteObjectKeys ?? [],
    sampleRate: row.sampleRate,
    durationSeconds: row.durationSeconds,
    byteCount: row.byteCount,
    savedAt: row.savedAt ? new Date(row.savedAt) : null,
    expiresAt: row.expiresAt ? new Date(row.expiresAt) : null,
    status: row.status,
    revision: row.revision ?? 0,
    error: row.error,
    updatedAt: new Date(row.updatedAt),
  };
}

function patchToSet(
  patch: Partial<Omit<GenerationRecord, "id" | "createdAt" | "revision">>,
): Record<string, unknown> {
  const set: Record<string, unknown> = {
    revision: sql`${ttsGeneration.revision} + 1`,
  };
  if (patch.title !== undefined) set.title = patch.title;
  if (patch.kind !== undefined) set.kind = patch.kind;
  if (patch.model !== undefined) set.model = patch.model;
  if (patch.requestId !== undefined) set.requestId = patch.requestId;
  if (patch.contentHash !== undefined) set.contentHash = patch.contentHash;
  if (patch.lines !== undefined) set.lines = patch.lines;
  if (patch.lineTimings !== undefined) set.lineTimings = patch.lineTimings;
  if (patch.tokenSync !== undefined) set.tokenSync = patch.tokenSync;
  if (patch.transcript !== undefined) set.transcript = patch.transcript;
  if (patch.wavObjectKey !== undefined) set.wavObjectKey = patch.wavObjectKey;
  if (patch.mp3ObjectKey !== undefined) set.mp3ObjectKey = patch.mp3ObjectKey;
  if (patch.obsoleteObjectKeys !== undefined) {
    set.obsoleteObjectKeys = patch.obsoleteObjectKeys;
  }
  if (patch.sampleRate !== undefined) set.sampleRate = patch.sampleRate;
  if (patch.durationSeconds !== undefined) set.durationSeconds = patch.durationSeconds;
  if (patch.byteCount !== undefined) set.byteCount = patch.byteCount;
  if (patch.savedAt !== undefined) set.savedAt = patch.savedAt ? new Date(patch.savedAt) : null;
  if (patch.expiresAt !== undefined) {
    set.expiresAt = patch.expiresAt ? new Date(patch.expiresAt) : null;
  }
  if (patch.status !== undefined) set.status = patch.status;
  if (patch.error !== undefined) set.error = patch.error;
  if (patch.updatedAt !== undefined) set.updatedAt = new Date(patch.updatedAt);
  return set;
}

function claimSql(claim: GenerationClaim): SQL | undefined {
  switch (claim.type) {
    case "reclaim":
      return and(
        isNull(ttsGeneration.savedAt),
        or(
          eq(ttsGeneration.status, "failed"),
          and(
            eq(ttsGeneration.status, "pending"),
            lte(ttsGeneration.updatedAt, new Date(claim.staleBeforeIso)),
          ),
          and(
            eq(ttsGeneration.status, "ready"),
            lte(ttsGeneration.expiresAt, new Date(claim.nowIso)),
          ),
        ),
      );
    case "cleanup":
      return and(
        isNull(ttsGeneration.savedAt),
        lte(ttsGeneration.expiresAt, new Date(claim.nowIso)),
        or(
          inArray(ttsGeneration.status, ["ready", "failed"]),
          and(
            eq(ttsGeneration.status, "pending"),
            lte(ttsGeneration.updatedAt, new Date(claim.staleBeforeIso)),
          ),
        ),
      );
    case "pending":
      return eq(ttsGeneration.status, "pending");
    case "ready":
      return eq(ttsGeneration.status, "ready");
    case "ready-unsaved":
      return and(eq(ttsGeneration.status, "ready"), isNull(ttsGeneration.savedAt));
    case "purging":
      return eq(ttsGeneration.status, "purging");
    case "not-purging":
      return ne(ttsGeneration.status, "purging");
  }
}

export const drizzleGenerationStore: GenerationStore = {
  async insert(row) {
    const [created] = await db
      .insert(ttsGeneration)
      .values({
        id: row.id,
        createdAt: new Date(row.createdAt),
        ...toInsertColumns(row),
      })
      .returning();
    return fromRow(created);
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
  async listCleanupCandidates(nowIso, staleBeforeIso, limit = 100) {
    const now = new Date(nowIso);
    const stale = new Date(staleBeforeIso);
    const rows = await db
      .select()
      .from(ttsGeneration)
      .where(
        or(
          eq(ttsGeneration.status, "purging"),
          sql`jsonb_array_length(coalesce(${ttsGeneration.obsoleteObjectKeys}, '[]'::jsonb)) > 0`,
          and(
            isNull(ttsGeneration.savedAt),
            lte(ttsGeneration.expiresAt, now),
            or(
              inArray(ttsGeneration.status, ["ready", "failed"]),
              and(
                eq(ttsGeneration.status, "pending"),
                lte(ttsGeneration.updatedAt, stale),
              ),
            ),
          ),
        ),
      )
      .orderBy(ttsGeneration.expiresAt)
      .limit(limit);
    return rows.map(fromRow);
  },
  async compareAndUpdate(id, expectedRevision, claim, patch) {
    const extra = claimSql(claim);
    const [updated] = await db
      .update(ttsGeneration)
      .set(patchToSet(patch))
      .where(
        and(
          ...[
            eq(ttsGeneration.id, id),
            eq(ttsGeneration.revision, expectedRevision),
            extra,
          ].filter((part): part is NonNullable<typeof part> => part != null),
        ),
      )
      .returning();
    return updated ? fromRow(updated) : null;
  },
  async deleteIfRevision(id, expectedRevision) {
    const [deleted] = await db
      .delete(ttsGeneration)
      .where(
        and(eq(ttsGeneration.id, id), eq(ttsGeneration.revision, expectedRevision)),
      )
      .returning();
    return deleted ? fromRow(deleted) : null;
  },
};
