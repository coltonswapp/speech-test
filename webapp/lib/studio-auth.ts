import { createHmac, timingSafeEqual } from "node:crypto";

export const AUTH_COOKIE = "studio_auth";

export function isPublicPath(pathname: string): boolean {
  return (
    pathname === "/login" ||
    pathname.startsWith("/api/login") ||
    pathname.startsWith("/api/logout") ||
    pathname.startsWith("/api/auth") ||
    pathname.startsWith("/api/public/") ||
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

export function authIsEnforced(): boolean {
  if (isAuthBypassed()) return false;
  return Boolean(
    isGoogleAuthConfigured() ||
      process.env.STUDIO_AGENT_TOKEN?.trim() ||
      process.env.APP_PASSPHRASE?.trim()
  );
}

export function bearerMatches(header: string | null): boolean {
  const expected = process.env.STUDIO_AGENT_TOKEN?.trim();
  if (!expected || !header) return false;
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) return false;
  const a = Buffer.from(token);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export function passphraseCookieValue(passphrase: string): string {
  const secret = authSecret();
  if (!secret) return passphrase;
  return createHmac("sha256", secret).update(passphrase).digest("hex");
}

export function passphraseCookieMatches(
  cookie: string | undefined,
  passphrase: string
): boolean {
  if (!cookie || !passphrase) return false;
  if (cookie === passphrase) return true;
  const expected = passphraseCookieValue(passphrase);
  const a = Buffer.from(cookie);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}
