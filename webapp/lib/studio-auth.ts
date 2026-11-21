import { timingSafeEqual } from "node:crypto";

type StoredAgentTokenLookup = (token: string) => Promise<boolean>;

export function isPublicPath(pathname: string): boolean {
  return (
    pathname === "/login" ||
    pathname.startsWith("/api/logout") ||
    pathname.startsWith("/api/auth") ||
    pathname.startsWith("/api/public/") ||
    pathname.startsWith("/hooks/") ||
    // The clip audio script (public/clip-fetch.mjs), fetched by curl with no
    // session. It holds no secrets; its access is the token in the command.
    pathname === "/clip-fetch.mjs" ||
    // Each /api/client route calls requireClientQaAccess (lib/client-auth.ts).
    pathname.startsWith("/api/client/") ||
    pathname.startsWith("/_next") ||
    pathname === "/favicon.ico"
  );
}

export function allowedEmails(): string[] {
  return (process.env.STUDIO_ALLOWED_EMAILS ?? "")
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean);
}

export function isEmailAllowed(email: string | null | undefined): boolean {
  if (!email) return false;
  return allowedEmails().includes(email.trim().toLowerCase());
}

export function googleClientId(): string {
  return (
    process.env.AUTH_GOOGLE_ID?.trim() ||
    process.env.GOOGLE_CLIENT_ID?.trim() ||
    ""
  );
}

export function googleClientSecret(): string {
  return (
    process.env.AUTH_GOOGLE_SECRET?.trim() ||
    process.env.GOOGLE_CLIENT_SECRET?.trim() ||
    ""
  );
}

export function authSecret(): string {
  return (
    process.env.AUTH_SECRET?.trim() ||
    process.env.NEXTAUTH_SECRET?.trim() ||
    ""
  );
}

export function isGoogleAuthConfigured(): boolean {
  return Boolean(authSecret() && googleClientId() && googleClientSecret());
}

export function isAuthBypassed(): boolean {
  if (process.env.NODE_ENV === "production") return false;
  return process.env.STUDIO_AUTH_BYPASS === "1";
}

/**
 * Production always enforces auth, even with no credentials configured (fail
 * closed). Locally, auth turns on once any credential is set.
 */
export function authIsEnforced(): boolean {
  if (isAuthBypassed()) return false;
  if (process.env.NODE_ENV === "production") return true;
  return Boolean(
    isGoogleAuthConfigured() ||
      process.env.STUDIO_AGENT_TOKEN?.trim() ||
      process.env.CONTENT_QA_CLIENT_TOKEN?.trim()
  );
}

function bearerToken(header: string | null): string {
  if (!header?.startsWith("Bearer ")) return "";
  return header.slice(7).trim();
}

function bearerEquals(header: string | null, expected: string | undefined): boolean {
  if (!expected) return false;
  const token = bearerToken(header);
  if (!token) return false;
  const a = Buffer.from(token);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/**
 * Stored-token lookup used when the env STUDIO_AGENT_TOKEN does not match.
 * Node's test runner never hits Neon (NODE_TEST_CONTEXT). Callers can pass a
 * lookup in tests; production uses the hashed rows in studio_agent_token.
 */
async function defaultStoredAgentTokenMatches(token: string): Promise<boolean> {
  if (process.env.NODE_TEST_CONTEXT) return false;
  if (!process.env.DATABASE_URL) return false;
  try {
    const { storedStudioAgentTokenMatches } = await import("./studio-agent-tokens-db");
    return await storedStudioAgentTokenMatches(token);
  } catch {
    return false;
  }
}

/**
 * Studio MCP / agent token: the env STUDIO_AGENT_TOKEN, or any active
 * unrevoked per-agent token from Settings → Agent tokens.
 * Does not accept cron or learner QA tokens.
 */
export async function studioAgentBearerMatches(
  header: string | null,
  storedTokenMatches: StoredAgentTokenLookup = defaultStoredAgentTokenMatches,
): Promise<boolean> {
  if (bearerEquals(header, process.env.STUDIO_AGENT_TOKEN?.trim())) return true;
  const token = bearerToken(header);
  if (!token) return false;
  return storedTokenMatches(token);
}

/** Vercel Cron secret. Only valid on `/api/cron/*` (see proxy). */
export function cronSecretMatches(header: string | null): boolean {
  return bearerEquals(header, process.env.CRON_SECRET?.trim());
}

/** Studio agent token or cron secret. */
export async function bearerMatches(header: string | null): Promise<boolean> {
  return (await studioAgentBearerMatches(header)) || cronSecretMatches(header);
}

/** Learner-client write token for content QA (parallel to Studio agent bearer). */
export function contentQaClientTokenMatches(header: string | null): boolean {
  return bearerEquals(header, process.env.CONTENT_QA_CLIENT_TOKEN?.trim());
}

/** Static token for `POST /hooks/shizen-note`. Never shipped in the app. */
export function shizenNoteWebhookTokenMatches(header: string | null): boolean {
  return bearerEquals(header, process.env.SHIZEN_NOTE_WEBHOOK_TOKEN?.trim());
}
