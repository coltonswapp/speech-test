import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import {
  bearerMatches,
  contentQaClientTokenMatches,
  cronSecretMatches,
  shizenNoteWebhookTokenMatches,
  studioAgentBearerMatches,
} from "./studio-auth";
import {
  createStudioAgentToken,
  storedStudioAgentTokenMatches,
  type StudioAgentTokenRecord,
  type StudioAgentTokenStore,
} from "./studio-agent-tokens";

const STUDIO = "sat_envtokenaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const CRON = "cron-secret-token-cccccccc";
const QA = "qa-learner-token-aaaaaaaa";
const NOTE = "shizen-note-webhook-token-dddd";

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
      return data.filter((item) => !item.revokedAt).map((item) => ({ ...item }));
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

describe("studioAgentBearerMatches", () => {
  const previous = {
    studio: process.env.STUDIO_AGENT_TOKEN,
    cron: process.env.CRON_SECRET,
    qa: process.env.CONTENT_QA_CLIENT_TOKEN,
    note: process.env.SHIZEN_NOTE_WEBHOOK_TOKEN,
  };

  before(() => {
    process.env.STUDIO_AGENT_TOKEN = STUDIO;
    process.env.CRON_SECRET = CRON;
    process.env.CONTENT_QA_CLIENT_TOKEN = QA;
    process.env.SHIZEN_NOTE_WEBHOOK_TOKEN = NOTE;
  });

  after(() => {
    const restore = (key: string, value: string | undefined) => {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    };
    restore("STUDIO_AGENT_TOKEN", previous.studio);
    restore("CRON_SECRET", previous.cron);
    restore("CONTENT_QA_CLIENT_TOKEN", previous.qa);
    restore("SHIZEN_NOTE_WEBHOOK_TOKEN", previous.note);
  });

  it("accepts the env STUDIO_AGENT_TOKEN without a stored lookup (migration fallback)", async () => {
    assert.equal(await studioAgentBearerMatches(`Bearer ${STUDIO}`), true);
    assert.equal(await studioAgentBearerMatches(`Bearer ${STUDIO}`, async () => false), true);
  });

  it("accepts an active per-agent token when the env token does not match", async () => {
    const store = memoryStore();
    const created = await createStudioAgentToken(store, "OpenBot");
    const lookup = (token: string) => storedStudioAgentTokenMatches(store, token);
    assert.equal(await studioAgentBearerMatches(`Bearer ${created.token}`, lookup), true);
    assert.equal(await studioAgentBearerMatches(`Bearer ${STUDIO}`, lookup), true);
    assert.equal(await studioAgentBearerMatches("Bearer nope", lookup), false);
  });

  it("does not treat cron, QA, or note-webhook secrets as agent tokens", async () => {
    assert.equal(await studioAgentBearerMatches(`Bearer ${CRON}`), false);
    assert.equal(await studioAgentBearerMatches(`Bearer ${QA}`), false);
    assert.equal(await studioAgentBearerMatches(`Bearer ${NOTE}`), false);
    assert.equal(cronSecretMatches(`Bearer ${CRON}`), true);
    assert.equal(contentQaClientTokenMatches(`Bearer ${QA}`), true);
    assert.equal(shizenNoteWebhookTokenMatches(`Bearer ${NOTE}`), true);
    assert.equal(await bearerMatches(`Bearer ${CRON}`), true);
    assert.equal(await bearerMatches(`Bearer ${STUDIO}`), true);
    assert.equal(cronSecretMatches(`Bearer ${STUDIO}`), false);
    assert.equal(contentQaClientTokenMatches(`Bearer ${STUDIO}`), false);
    assert.equal(shizenNoteWebhookTokenMatches(`Bearer ${STUDIO}`), false);
  });
});
