import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { NextRequest } from "next/server";
import { rejectLearnerQaAccess } from "./access";

const QA = "qa-learner-token-aaaaaaaa";
const STUDIO = "studio-agent-token-bbbbbbbb";

function bearerRequest(token?: string, path = "http://localhost/api/generate") {
  const headers = new Headers();
  if (token) headers.set("authorization", `Bearer ${token}`);
  return new NextRequest(path, { headers });
}

describe("rejectLearnerQaAccess", () => {
  const previous = {
    qa: process.env.CONTENT_QA_CLIENT_TOKEN,
    studio: process.env.STUDIO_AGENT_TOKEN,
  };

  before(() => {
    process.env.CONTENT_QA_CLIENT_TOKEN = QA;
    process.env.STUDIO_AGENT_TOKEN = STUDIO;
  });

  after(() => {
    if (previous.qa === undefined) delete process.env.CONTENT_QA_CLIENT_TOKEN;
    else process.env.CONTENT_QA_CLIENT_TOKEN = previous.qa;
    if (previous.studio === undefined) delete process.env.STUDIO_AGENT_TOKEN;
    else process.env.STUDIO_AGENT_TOKEN = previous.studio;
  });

  it("forbids the learner QA token on generate reads", async () => {
    const denied = rejectLearnerQaAccess(bearerRequest(QA, "http://localhost/api/generate"));
    assert.ok(denied);
    assert.equal(denied.status, 403);
    const detail = rejectLearnerQaAccess(
      bearerRequest(QA, "http://localhost/api/generate/abc/audio"),
    );
    assert.equal(detail?.status, 403);
    const timing = rejectLearnerQaAccess(
      bearerRequest(QA, "http://localhost/api/generate/abc/timing"),
    );
    assert.equal(timing?.status, 403);
  });

  it("allows the Studio agent bearer", () => {
    assert.equal(rejectLearnerQaAccess(bearerRequest(STUDIO)), null);
  });

  it("does not invent a cookie check; sessioned Studio traffic is left to proxy", () => {
    assert.equal(rejectLearnerQaAccess(bearerRequest(undefined)), null);
  });
});

describe("generate route files", () => {
  const files = [
    "app/api/generate/route.ts",
    "app/api/generate/upload/route.ts",
    "app/api/generate/[id]/route.ts",
    "app/api/generate/[id]/audio/route.ts",
    "app/api/generate/[id]/timing/route.ts",
    "app/api/generate/[id]/align/route.ts",
  ];

  it("call rejectLearnerQaAccess on every HTTP handler", () => {
    const cwd = process.cwd();
    const root = cwd.endsWith("webapp") ? cwd : join(cwd, "webapp");
    for (const file of files) {
      const src = readFileSync(join(root, file), "utf8");
      const methods = [...src.matchAll(/export async function (GET|POST|PATCH|DELETE)/g)];
      const guards = [...src.matchAll(/rejectLearnerQaAccess\(request\)/g)];
      assert.ok(methods.length > 0, `${file} exports handlers`);
      assert.equal(
        guards.length,
        methods.length,
        `${file} must guard each handler (found ${guards.length} vs ${methods.length})`,
      );
    }
  });
});
