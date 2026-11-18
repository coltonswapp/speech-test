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
 * Claims of a Firebase ID token from a signed-in (non-anonymous) app user,
 * or null.
 *
 * Verified with jose, the same checks as firebase-admin's verifyIdToken
 * (RS256, Google keys, issuer, audience, expiry, non-empty sub).
 * firebase-admin/auth itself fails to load on Vercel's Node 24
 * (jwks-rsa require()s ESM-only jose).
 */
async function verifiedFirebaseUser(
  header: string | null,
  keys: JWTVerifyGetKey,
): Promise<{ uid: string; staff: boolean } | null> {
  const token = bearer(header);
  if (token.split(".").length !== 3) return null;
  try {
    const { payload } = await jwtVerify(token, keys, {
      algorithms: ["RS256"],
      issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
      audience: FIREBASE_PROJECT_ID,
    });
    if (typeof payload.sub !== "string" || payload.sub.length === 0) return null;
    const firebase = payload.firebase as { sign_in_provider?: string } | undefined;
    if (firebase?.sign_in_provider === "anonymous") return null;
    return { uid: payload.sub, staff: payload.staff === true };
  } catch {
    return null;
  }
}

/**
 * A Firebase ID token from the iOS app whose user has the `staff: true`
 * custom claim (set with services/llm-gateway/scripts/set-staff-claim.ts).
 * The token is signed by Firebase, so the claim can't be forged.
 */
export async function firebaseStaffTokenMatches(
  header: string | null,
  keys: JWTVerifyGetKey = firebaseJwks,
): Promise<boolean> {
  return (await verifiedFirebaseUser(header, keys))?.staff === true;
}

/** Firebase uid of any signed-in (Apple/Google) learner, or null. */
export async function firebaseLearnerUid(
  header: string | null,
  keys: JWTVerifyGetKey = firebaseJwks,
): Promise<string | null> {
  return (await verifiedFirebaseUser(header, keys))?.uid ?? null;
}

/**
 * Learner-facing client routes (e.g. clip feedback): any signed-in user.
 * Returns the uid to attribute the write to, or a 401 response.
 * The DEBUG QA token maps to `qa-client` so simulator builds can post;
 * with auth off (local dev) everything is `local-dev`.
 */
export async function requireClientLearner(
  request: NextRequest,
): Promise<{ uid: string } | NextResponse> {
  if (!authIsEnforced()) return { uid: "local-dev" };
  const authorization = request.headers.get("authorization");
  const uid = await firebaseLearnerUid(authorization);
  if (uid) return { uid };
  if (contentQaClientTokenMatches(authorization)) return { uid: "qa-client" };
  return NextResponse.json({ error: "Sign in to send feedback" }, { status: 401 });
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
