import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { NextRequest } from "next/server";
import { encode } from "next-auth/jwt";
import { requireGenerateAccess } from "./access";

const QA = "qa-learner-token-aaaaaaaa";
const STUDIO = "studio-agent-token-bbbbbbbb";
const CRON = "cron-secret-token-cccccccc";
const SECRET = "test-auth-secret-at-least-32-chars!!";
const EMAIL = "studio@example.com";

function request(path = "http://localhost/api/generate", init?: { token?: string; cookie?: string }) {
  const headers = new Headers();
  if (init?.token) headers.set("authorization", `Bearer ${init.token}`);
  if (init?.cookie) headers.set("cookie", init.cookie);
  return new NextRequest(path, { headers });
}

async function sessionCookie(email: string, maxAge: number) {
  const token = await encode({
    token: { email, sub: "user-1" },
    secret: SECRET,
    maxAge,
  });
  return `next-auth.session-token=${token}`;
}

describe("requireGenerateAccess", () => {
  const previous = {
    qa: process.env.CONTENT_QA_CLIENT_TOKEN,
    studio: process.env.STUDIO_AGENT_TOKEN,
    cron: process.env.CRON_SECRET,
    authSecret: process.env.AUTH_SECRET,
    nextAuthSecret: process.env.NEXTAUTH_SECRET,
    googleId: process.env.AUTH_GOOGLE_ID,
    googleSecret: process.env.AUTH_GOOGLE_SECRET,
    emails: process.env.STUDIO_ALLOWED_EMAILS,
    bypass: process.env.STUDIO_AUTH_BYPASS,
    passphrase: process.env.APP_PASSPHRASE,
    nextAuthUrl: process.env.NEXTAUTH_URL,
  };

  before(() => {
    process.env.CONTENT_QA_CLIENT_TOKEN = QA;
    process.env.STUDIO_AGENT_TOKEN = STUDIO;
    process.env.CRON_SECRET = CRON;
    process.env.AUTH_SECRET = SECRET;
    process.env.NEXTAUTH_SECRET = SECRET;
    process.env.AUTH_GOOGLE_ID = "test-google-id";
    process.env.AUTH_GOOGLE_SECRET = "test-google-secret";
    process.env.STUDIO_ALLOWED_EMAILS = EMAIL;
    process.env.NEXTAUTH_URL = "http://localhost:3000";
    delete process.env.STUDIO_AUTH_BYPASS;
    delete process.env.APP_PASSPHRASE;
  });

  after(() => {
    const restore = (key: string, value: string | undefined) => {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    };
    restore("CONTENT_QA_CLIENT_TOKEN", previous.qa);
    restore("STUDIO_AGENT_TOKEN", previous.studio);
    restore("CRON_SECRET", previous.cron);
    restore("AUTH_SECRET", previous.authSecret);
    restore("NEXTAUTH_SECRET", previous.nextAuthSecret);
    restore("AUTH_GOOGLE_ID", previous.googleId);
    restore("AUTH_GOOGLE_SECRET", previous.googleSecret);
    restore("STUDIO_ALLOWED_EMAILS", previous.emails);
    restore("STUDIO_AUTH_BYPASS", previous.bypass);
    restore("APP_PASSPHRASE", previous.passphrase);
    restore("NEXTAUTH_URL", previous.nextAuthUrl);
  });

  it("denies a forged next-auth.session-token cookie", async () => {
    const denied = await requireGenerateAccess(
      request("http://localhost/api/generate", {
        cookie: "next-auth.session-token=fake",
      }),
    );
    assert.ok(denied);
    assert.equal(denied.status, 401);
    const audio = await requireGenerateAccess(
      request("http://localhost/api/generate/abc/audio", {
        cookie: "next-auth.session-token=fake",
      }),
    );
    assert.equal(audio?.status, 401);
  });

  it("denies an expired next-auth session JWT", async () => {
    const cookie = await sessionCookie(EMAIL, -60);
    const denied = await requireGenerateAccess(request("http://localhost/api/generate", { cookie }));
    assert.ok(denied);
    assert.equal(denied.status, 401);
  });

  it("allows a verified next-auth session for an allowed email", async () => {
    const cookie = await sessionCookie(EMAIL, 60 * 60);
    const allowed = await requireGenerateAccess(request("http://localhost/api/generate", { cookie }));
    assert.equal(allowed, null);
    const audio = await requireGenerateAccess(
      request("http://localhost/api/generate/abc/audio", { cookie }),
    );
    assert.equal(audio, null);
  });

  it("denies a verified session whose email is not allowlisted", async () => {
    const cookie = await sessionCookie("other@example.com", 60 * 60);
    const denied = await requireGenerateAccess(request("http://localhost/api/generate", { cookie }));
    assert.ok(denied);
    assert.equal(denied.status, 401);
  });

  it("allows the Studio agent bearer and forbids learner QA and cron tokens", async () => {
    assert.equal(await requireGenerateAccess(request("http://localhost/api/generate", { token: STUDIO })), null);
    const qa = await requireGenerateAccess(request("http://localhost/api/generate", { token: QA }));
    assert.equal(qa?.status, 403);
    const cron = await requireGenerateAccess(request("http://localhost/api/generate", { token: CRON }));
    assert.equal(cron?.status, 401);
    const missing = await requireGenerateAccess(request());
    assert.equal(missing?.status, 401);
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

  it("await requireGenerateAccess on every HTTP handler", () => {
    const cwd = process.cwd();
    const root = cwd.endsWith("webapp") ? cwd : join(cwd, "webapp");
    for (const file of files) {
      const src = readFileSync(join(root, file), "utf8");
      const methods = [...src.matchAll(/export async function (GET|POST|PATCH|DELETE)/g)];
      const guards = [...src.matchAll(/await requireGenerateAccess\(request\)/g)];
      assert.ok(methods.length > 0, `${file} exports handlers`);
      assert.equal(
        guards.length,
        methods.length,
        `${file} must guard each handler (found ${guards.length} vs ${methods.length})`,
      );
    }
  });
});
