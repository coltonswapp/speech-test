import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { NextRequest } from "next/server";
import { SignJWT, createLocalJWKSet, exportJWK, generateKeyPair } from "jose";
import { firebaseStaffTokenMatches, isClientQaAuthorized } from "./client-auth";
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

describe("firebaseStaffTokenMatches", () => {
  const PROJECT = "shizen-b453f";
  let sign: (claims: Record<string, unknown>, opts?: { aud?: string; iss?: string; exp?: number }) => Promise<string>;
  let keys: ReturnType<typeof createLocalJWKSet>;

  before(async () => {
    const { publicKey, privateKey } = await generateKeyPair("RS256");
    const jwk = { ...(await exportJWK(publicKey)), kid: "k1", alg: "RS256" };
    keys = createLocalJWKSet({ keys: [jwk] });
    sign = (claims, opts = {}) =>
      new SignJWT(claims)
        .setProtectedHeader({ alg: "RS256", kid: "k1" })
        .setIssuer(opts.iss ?? `https://securetoken.google.com/${PROJECT}`)
        .setAudience(opts.aud ?? PROJECT)
        .setSubject("uid-1")
        .setIssuedAt()
        .setExpirationTime(opts.exp ?? Math.floor(Date.now() / 1000) + 3600)
        .sign(privateKey);
  });

  const check = async (token: string) => firebaseStaffTokenMatches(`Bearer ${token}`, keys);

  it("accepts a valid token with staff: true", async () => {
    assert.equal(await check(await sign({ staff: true, firebase: { sign_in_provider: "google.com" } })), true);
  });

  it("rejects no claim, wrong project, expired, and anonymous", async () => {
    assert.equal(await check(await sign({})), false);
    assert.equal(await check(await sign({ staff: "true" })), false);
    assert.equal(await check(await sign({ staff: true }, { aud: "other-project" })), false);
    assert.equal(await check(await sign({ staff: true }, { iss: "https://securetoken.google.com/other" })), false);
    assert.equal(await check(await sign({ staff: true }, { exp: Math.floor(Date.now() / 1000) - 600 })), false);
    assert.equal(await check(await sign({ staff: true, firebase: { sign_in_provider: "anonymous" } })), false);
  });

  it("rejects a token signed by a key Google didn't publish", async () => {
    const other = await generateKeyPair("RS256");
    const forged = await new SignJWT({ staff: true })
      .setProtectedHeader({ alg: "RS256", kid: "k1" })
      .setIssuer(`https://securetoken.google.com/${PROJECT}`)
      .setAudience(PROJECT)
      .setSubject("uid-1")
      .setExpirationTime("1h")
      .sign(other.privateKey);
    assert.equal(await check(forged), false);
    // And against Google's real keys.
    assert.equal(await firebaseStaffTokenMatches(`Bearer ${forged}`), false);
  });
});
