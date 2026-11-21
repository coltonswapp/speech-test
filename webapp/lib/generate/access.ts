import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getToken } from "next-auth/jwt";
import {
  authIsEnforced,
  authSecret,
  contentQaClientTokenMatches,
  cronSecretMatches,
  isEmailAllowed,
  isGoogleAuthConfigured,
  studioAgentBearerMatches,
} from "@/lib/studio-auth";

function unauthorized(): NextResponse {
  return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
}

function forbidden(): NextResponse {
  return NextResponse.json({ error: "Forbidden" }, { status: 403 });
}

/**
 * True only for a next-auth session JWT that decrypts with our secret, has not
 * expired, and names an allowlisted email. Cookie presence alone proves
 * nothing: anyone can send a cookie named `next-auth.session-token`.
 */
export async function hasVerifiedStudioSession(request: NextRequest): Promise<boolean> {
  if (!isGoogleAuthConfigured()) return false;
  try {
    const token = await getToken({ req: request, secret: authSecret() });
    const email = typeof token?.email === "string" ? token.email : null;
    return Boolean(token && isEmailAllowed(email));
  } catch {
    return false;
  }
}

/**
 * The single Studio gate, run by proxy.ts for every non-public path.
 *
 * - Studio agent bearer: any route.
 * - Cron secret: `/api/cron/*` only.
 * - `/api/client/*` is not gated here: those routes call
 *   requireClientQaAccess (lib/client-auth.ts), which also accepts the
 *   learner QA token and Firebase staff ID tokens.
 * - Verified Google session for an allowlisted email: any route.
 */
export async function isStudioRequestAllowed(request: NextRequest): Promise<boolean> {
  if (!authIsEnforced()) return true;

  const { pathname } = request.nextUrl;
  const authorization = request.headers.get("authorization");

  if (await studioAgentBearerMatches(authorization)) return true;
  if (pathname.startsWith("/api/cron/") && cronSecretMatches(authorization)) return true;
  return hasVerifiedStudioSession(request);
}

/**
 * Settings that mint or revoke credentials: a verified allowlisted Google
 * session only. Agent bearers can use Studio APIs but cannot issue more tokens.
 */
export async function requireSignedInStudioAdmin(
  request: NextRequest,
): Promise<NextResponse | null> {
  if (!authIsEnforced()) return null;
  if (await hasVerifiedStudioSession(request)) return null;
  return unauthorized();
}

/**
 * Generate APIs verify credentials themselves, on top of the proxy.
 * Allowed: Studio agent bearer, or a verified allowlisted Google session.
 * Learner QA bearer is forbidden.
 */
export async function requireGenerateAccess(
  request: NextRequest,
): Promise<NextResponse | null> {
  if (!authIsEnforced()) return null;

  const authorization = request.headers.get("authorization");
  if (await studioAgentBearerMatches(authorization)) return null;
  if (contentQaClientTokenMatches(authorization)) return forbidden();
  if (await hasVerifiedStudioSession(request)) return null;
  return unauthorized();
}
