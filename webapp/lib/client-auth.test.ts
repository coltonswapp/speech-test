import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { NextRequest } from "next/server";
import { isClientQaAuthorized } from "./client-auth";
import { isPublicPath } from "./studio-auth";

const QA = "qa-learner-token-aaaaaaaa";
const STUDIO = "studio-agent-token-bbbbbbbb";

function request(token?: string) {
  const headers = new Headers();
  if (token) headers.set("authorization", `Bearer ${token}`);
  return new NextRequest("http://localhost/api/client/content-qa/notes", { headers });
}

describe("isClientQaAuthorized", () => {
  const prev = { qa: process.env.CONTENT_QA_CLIENT_TOKEN, studio: process.env.STUDIO_AGENT_TOKEN };
  before(() => {
    process.env.CONTENT_QA_CLIENT_TOKEN = QA;
    process.env.STUDIO_AGENT_TOKEN = STUDIO;
  });
  after(() => {
    for (const [key, value] of [["CONTENT_QA_CLIENT_TOKEN", prev.qa], ["STUDIO_AGENT_TOKEN", prev.studio]] as const) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  it("accepts the QA token and the agent bearer", async () => {
    assert.equal(await isClientQaAuthorized(request(QA)), true);
    assert.equal(await isClientQaAuthorized(request(STUDIO)), true);
  });

  it("rejects missing, wrong, and forged JWT bearers", async () => {
    assert.equal(await isClientQaAuthorized(request()), false);
    assert.equal(await isClientQaAuthorized(request("nope")), false);
    // Shaped like a JWT but not signed by Firebase.
    const forged = [
      Buffer.from('{"alg":"RS256","kid":"x"}').toString("base64url"),
      Buffer.from('{"staff":true,"sub":"u"}').toString("base64url"),
      "sig",
    ].join(".");
    assert.equal(await isClientQaAuthorized(request(forged)), false);
  });
});

describe("/api/client route files", () => {
  const root = join(process.cwd(), "app/api/client");
  const files: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) walk(path);
      else if (name === "route.ts") files.push(path);
    }
  };
  walk(root);

  it("are skipped by the proxy", () => {
    assert.equal(isPublicPath("/api/client/content-qa/notes"), true);
  });

  it("check access in every HTTP handler", () => {
    assert.ok(files.length >= 3);
    for (const file of files) {
      const src = readFileSync(file, "utf8");
      const handlers = [...src.matchAll(/export async function (GET|POST|PUT|PATCH|DELETE)\b/g)].length;
      const guards = [...src.matchAll(/requireClientQaAccess\(request\)|handleNotePost\(request, isClientQaAuthorized\)/g)].length;
      assert.ok(handlers > 0, file);
      assert.equal(guards, handlers, file);
    }
  });
});
