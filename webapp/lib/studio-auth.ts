import { timingSafeEqual } from "node:crypto";

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

function bearerEquals(header: string | null, expected: string | undefined): boolean {
  if (!expected || !header) return false;
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) return false;
  const a = Buffer.from(token);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** Studio MCP / agent token. Does not accept cron or learner QA tokens. */
export function studioAgentBearerMatches(header: string | null): boolean {
  return bearerEquals(header, process.env.STUDIO_AGENT_TOKEN?.trim());
}

/** Vercel Cron secret. Only valid on `/api/cron/*` (see proxy). */
export function cronSecretMatches(header: string | null): boolean {
  return bearerEquals(header, process.env.CRON_SECRET?.trim());
}

/** Studio agent token or cron secret. */
export function bearerMatches(header: string | null): boolean {
  return studioAgentBearerMatches(header) || cronSecretMatches(header);
}

/** Learner-client write token for content QA (parallel to Studio agent bearer). */
export function contentQaClientTokenMatches(header: string | null): boolean {
  return bearerEquals(header, process.env.CONTENT_QA_CLIENT_TOKEN?.trim());
}

/** Static token for `POST /hooks/shizen-note`. Never shipped in the app. */
export function shizenNoteWebhookTokenMatches(header: string | null): boolean {
  return bearerEquals(header, process.env.SHIZEN_NOTE_WEBHOOK_TOKEN?.trim());
}
