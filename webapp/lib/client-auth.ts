import "server-only";

import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getAuth } from "firebase-admin/auth";
import { hasVerifiedStudioSession } from "@/lib/generate/access";
import { getAdminApp } from "@/lib/usage/firebase-admin";
import {
  authIsEnforced,
  contentQaClientTokenMatches,
  studioAgentBearerMatches,
} from "@/lib/studio-auth";

function bearer(header: string | null): string {
  return header?.startsWith("Bearer ") ? header.slice(7).trim() : "";
}

/**
 * A Firebase ID token from the iOS app whose user has the `staff: true`
 * custom claim (set with services/llm-gateway/scripts/set-staff-claim.ts).
 * The token is signed by Firebase, so the claim can't be forged.
 */
export async function firebaseStaffTokenMatches(header: string | null): Promise<boolean> {
  const token = bearer(header);
  // Firebase ID tokens are JWTs; skip the network-backed verify for anything else.
  if (token.split(".").length !== 3) return false;
  try {
    const decoded = await getAuth(getAdminApp()).verifyIdToken(token);
    return decoded.staff === true;
  } catch {
    return false;
  }
}

/**
 * `/api/client/*` is skipped by proxy.ts so these routes can verify Firebase
 * ID tokens here (firebase-admin is too heavy for the proxy).
 *
 * Allowed: Firebase staff token (Release iOS), CONTENT_QA_CLIENT_TOKEN
 * (DEBUG iOS only), Studio agent bearer, or a verified Studio session.
 */
export async function isClientQaAuthorized(request: NextRequest): Promise<boolean> {
  if (!authIsEnforced()) return true;
  const authorization = request.headers.get("authorization");
  if (contentQaClientTokenMatches(authorization)) return true;
  if (studioAgentBearerMatches(authorization)) return true;
  if (await firebaseStaffTokenMatches(authorization)) return true;
  return hasVerifiedStudioSession(request);
}

export async function requireClientQaAccess(request: NextRequest): Promise<NextResponse | null> {
  if (await isClientQaAuthorized(request)) return null;
  return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
}
