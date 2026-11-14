import "server-only";

import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import { hasVerifiedStudioSession } from "@/lib/generate/access";
import {
  authIsEnforced,
  contentQaClientTokenMatches,
  studioAgentBearerMatches,
} from "@/lib/studio-auth";

function bearer(header: string | null): string {
  return header?.startsWith("Bearer ") ? header.slice(7).trim() : "";
}

const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID?.trim() || "shizen-b453f";

// Google's public keys for Firebase ID tokens. jose caches them and refetches
// on an unknown `kid`.
const firebaseJwks = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);

/**
 * A Firebase ID token from the iOS app whose user has the `staff: true`
 * custom claim (set with services/llm-gateway/scripts/set-staff-claim.ts).
 * The token is signed by Firebase, so the claim can't be forged.
 *
 * Verified with jose, the same checks as firebase-admin's verifyIdToken
 * (RS256, Google keys, issuer, audience, expiry, non-empty sub).
 * firebase-admin/auth itself fails to load on Vercel's Node 24
 * (jwks-rsa require()s ESM-only jose).
 */
export async function firebaseStaffTokenMatches(
  header: string | null,
  keys: JWTVerifyGetKey = firebaseJwks,
): Promise<boolean> {
  const token = bearer(header);
  if (token.split(".").length !== 3) return false;
  try {
    const { payload } = await jwtVerify(token, keys, {
      algorithms: ["RS256"],
      issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
      audience: FIREBASE_PROJECT_ID,
    });
    if (typeof payload.sub !== "string" || payload.sub.length === 0) return false;
    const firebase = payload.firebase as { sign_in_provider?: string } | undefined;
    if (firebase?.sign_in_provider === "anonymous") return false;
    return payload.staff === true;
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
