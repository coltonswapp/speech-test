import "server-only";
import { and, desc, eq, isNull } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { studioAgentToken } from "@/lib/db/schema";
import {
  storedStudioAgentTokenMatches as matchAgainstStore,
  type StudioAgentTokenRecord,
  type StudioAgentTokenStore,
} from "@/lib/studio-agent-tokens";

function fromRow(row: typeof studioAgentToken.$inferSelect): StudioAgentTokenRecord {
  return {
    id: row.id,
    name: row.name,
    tokenHash: row.tokenHash,
    prefix: row.prefix,
    createdAt: row.createdAt,
    lastUsedAt: row.lastUsedAt,
    revokedAt: row.revokedAt,
  };
}

export const drizzleAgentTokenStore: StudioAgentTokenStore = {
  async insert(row) {
    const [created] = await db
      .insert(studioAgentToken)
      .values({
        id: row.id,
        name: row.name,
        tokenHash: row.tokenHash,
        prefix: row.prefix,
        createdAt: row.createdAt,
        lastUsedAt: row.lastUsedAt,
        revokedAt: row.revokedAt,
      })
      .returning();
    return fromRow(created);
  },
  async findActiveByHash(tokenHash) {
    const [row] = await db
      .select()
      .from(studioAgentToken)
      .where(and(eq(studioAgentToken.tokenHash, tokenHash), isNull(studioAgentToken.revokedAt)))
      .limit(1);
    return row ? fromRow(row) : null;
  },
  async findActiveByName(name) {
    const [row] = await db
      .select()
      .from(studioAgentToken)
      .where(and(eq(studioAgentToken.name, name), isNull(studioAgentToken.revokedAt)))
      .limit(1);
    return row ? fromRow(row) : null;
  },
  async listActive() {
    const rows = await db
      .select()
      .from(studioAgentToken)
      .where(isNull(studioAgentToken.revokedAt))
      .orderBy(desc(studioAgentToken.createdAt));
    return rows.map(fromRow);
  },
  async revoke(id, at) {
    const [row] = await db
      .update(studioAgentToken)
      .set({ revokedAt: at })
      .where(and(eq(studioAgentToken.id, id), isNull(studioAgentToken.revokedAt)))
      .returning();
    return row ? fromRow(row) : null;
  },
  async touchLastUsed(id, at) {
    await db
      .update(studioAgentToken)
      .set({ lastUsedAt: at })
      .where(eq(studioAgentToken.id, id));
  },
};

/** Used by studioAgentBearerMatches. Swallows lookup failures so env auth still works. */
export async function storedStudioAgentTokenMatches(token: string): Promise<boolean> {
  try {
    return await matchAgainstStore(drizzleAgentTokenStore, token);
  } catch {
    return false;
  }
}
