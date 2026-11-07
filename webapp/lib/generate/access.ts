import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getToken } from "next-auth/jwt";
import {
  AUTH_COOKIE,
  authIsEnforced,
  authSecret,
  contentQaClientTokenMatches,
  isEmailAllowed,
  isGoogleAuthConfigured,
  passphraseCookieMatches,
  studioAgentBearerMatches,
} from "@/lib/studio-auth";

function unauthorized(): NextResponse {
  return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
}

function forbidden(): NextResponse {
  return NextResponse.json({ error: "Forbidden" }, { status: 403 });
}

/**
 * Generate APIs verify credentials themselves. Proxy cookie presence is not
 * enough: a forged `next-auth.session-token` must not read audio or history.
 *
 * Allowed: Studio agent bearer, verified passphrase cookie, or a next-auth JWT
 * whose email is on STUDIO_ALLOWED_EMAILS. Learner QA bearer is forbidden.
 */
export async function requireGenerateAccess(
  request: NextRequest,
): Promise<NextResponse | null> {
  if (!authIsEnforced()) return null;

  const authorization = request.headers.get("authorization");
  if (studioAgentBearerMatches(authorization)) return null;
  if (contentQaClientTokenMatches(authorization)) return forbidden();

  const passphrase = process.env.APP_PASSPHRASE?.trim() ?? "";
  if (
    passphrase &&
    passphraseCookieMatches(request.cookies.get(AUTH_COOKIE)?.value, passphrase)
  ) {
    return null;
  }

  if (isGoogleAuthConfigured()) {
    const token = await getToken({
      req: request,
      secret: authSecret(),
    });
    const email = typeof token?.email === "string" ? token.email : null;
    if (token && isEmailAllowed(email)) return null;
  }

  return unauthorized();
}

/** @deprecated Use requireGenerateAccess */
export function rejectLearnerQaAccess(request: NextRequest): NextResponse | null {
  const authorization = request.headers.get("authorization");
  if (contentQaClientTokenMatches(authorization) && !studioAgentBearerMatches(authorization)) {
    return forbidden();
  }
  return null;
}

/** @deprecated Use requireGenerateAccess */
export function forbidContentQaOnly(request: NextRequest): NextResponse | null {
  return rejectLearnerQaAccess(request);
}
