import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  AgentTokenError,
  LAST_USED_TOUCH_MS,
  STUDIO_AGENT_TOKEN_DISPLAY_PREFIX_LENGTH,
  STUDIO_AGENT_TOKEN_PREFIX,
  createStudioAgentToken,
  generateStudioAgentToken,
  hashStudioAgentToken,
  listStudioAgentTokens,
  revokeStudioAgentToken,
  storedStudioAgentTokenMatches,
  type StudioAgentTokenRecord,
  type StudioAgentTokenStore,
} from "./studio-agent-tokens";

function memoryStore(rows: StudioAgentTokenRecord[] = []): StudioAgentTokenStore {
  const data = rows.map((row) => ({ ...row }));
  return {
    async insert(row) {
      data.push({ ...row });
      return { ...row };
    },
    async findActiveByHash(tokenHash) {
      const row = data.find((item) => item.tokenHash === tokenHash && !item.revokedAt);
      return row ? { ...row } : null;
    },
    async findActiveByName(name) {
      const row = data.find((item) => item.name === name && !item.revokedAt);
      return row ? { ...row } : null;
    },
    async listActive() {
      return data
        .filter((item) => !item.revokedAt)
        .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
        .map((item) => ({ ...item }));
    },
    async revoke(id, at) {
      const row = data.find((item) => item.id === id && !item.revokedAt);
      if (!row) return null;
      row.revokedAt = at;
      return { ...row };
    },
    async touchLastUsed(id, at) {
      const row = data.find((item) => item.id === id);
      if (row) row.lastUsedAt = at;
    },
  };
}

describe("generateStudioAgentToken", () => {
  it("uses sat_ plus CSPRNG hex and a short display prefix", () => {
    const generated = generateStudioAgentToken();
    assert.equal(generated.token.startsWith(STUDIO_AGENT_TOKEN_PREFIX), true);
    assert.match(generated.token, /^sat_[0-9a-f]{64}$/);
    assert.equal(generated.prefix, generated.token.slice(0, STUDIO_AGENT_TOKEN_DISPLAY_PREFIX_LENGTH));
    assert.equal(generated.hash, hashStudioAgentToken(generated.token));
    assert.equal(generated.hash.length, 64);
    assert.notEqual(generateStudioAgentToken().token, generated.token);
  });
});

describe("create / list / revoke", () => {
  it("stores only the hash and returns plaintext once", async () => {
    const store = memoryStore();
    const created = await createStudioAgentToken(store, "  OpenBot  ", () => new Date("2026-11-21T00:00:00Z"));
    assert.equal(created.token.startsWith("sat_"), true);
    assert.equal(created.tokenRecord.name, "OpenBot");
    assert.equal(created.tokenRecord.prefix, created.token.slice(0, 12));
    assert.equal("tokenHash" in created.tokenRecord, false);
    const listed = await listStudioAgentTokens(store);
    assert.equal(listed.length, 1);
    assert.equal(listed[0].name, "OpenBot");
    assert.equal(JSON.stringify(listed).includes(created.token), false);
    assert.equal(JSON.stringify(listed).includes(hashStudioAgentToken(created.token)), false);
  });

  it("rejects a duplicate active name and allows reuse after revoke", async () => {
    const store = memoryStore();
    const first = await createStudioAgentToken(store, "Kenji");
    await assert.rejects(
      () => createStudioAgentToken(store, "Kenji"),
      (error: unknown) => error instanceof AgentTokenError && error.code === "name_taken",
    );
    await revokeStudioAgentToken(store, first.tokenRecord.id, () => new Date("2026-11-21T01:00:00Z"));
    const second = await createStudioAgentToken(store, "Kenji");
    assert.notEqual(second.token, first.token);
    assert.equal((await listStudioAgentTokens(store)).length, 1);
  });

  it("revoke of an unknown id fails", async () => {
    await assert.rejects(
      () => revokeStudioAgentToken(memoryStore(), "atk_missing"),
      (error: unknown) => error instanceof AgentTokenError && error.code === "not_found",
    );
  });
});

describe("storedStudioAgentTokenMatches", () => {
  it("accepts an active token and rejects revoked or unknown ones", async () => {
    const store = memoryStore();
    const created = await createStudioAgentToken(store, "Grok connector");
    assert.equal(await storedStudioAgentTokenMatches(store, created.token), true);
    assert.equal(await storedStudioAgentTokenMatches(store, "sat_" + "0".repeat(64)), false);
    await revokeStudioAgentToken(store, created.tokenRecord.id);
    assert.equal(await storedStudioAgentTokenMatches(store, created.token), false);
  });

  it("throttles last_used_at writes", async () => {
    const store = memoryStore();
    const t0 = new Date("2026-11-21T12:00:00Z");
    const created = await createStudioAgentToken(store, "OpenBot", () => t0);
    assert.equal(await storedStudioAgentTokenMatches(store, created.token, () => t0), true);
    const afterFirst = await store.findActiveByHash(hashStudioAgentToken(created.token));
    assert.equal(afterFirst?.lastUsedAt?.toISOString(), t0.toISOString());

    const soon = new Date(t0.getTime() + LAST_USED_TOUCH_MS - 1);
    assert.equal(await storedStudioAgentTokenMatches(store, created.token, () => soon), true);
    const afterSoon = await store.findActiveByHash(hashStudioAgentToken(created.token));
    assert.equal(afterSoon?.lastUsedAt?.toISOString(), t0.toISOString());

    const later = new Date(t0.getTime() + LAST_USED_TOUCH_MS);
    assert.equal(await storedStudioAgentTokenMatches(store, created.token, () => later), true);
    const afterLater = await store.findActiveByHash(hashStudioAgentToken(created.token));
    assert.equal(afterLater?.lastUsedAt?.toISOString(), later.toISOString());
  });
});
