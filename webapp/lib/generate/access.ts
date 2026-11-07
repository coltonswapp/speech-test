import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { bearerMatches, contentQaClientTokenMatches } from "@/lib/studio-auth";

/**
 * Learner content-QA tokens pass the Studio proxy (`apiBearerMatches`) but must
 * not read Generate audio, text, timing, or history. Studio agent bearer and
 * cookie/Google sessions (already gated by proxy) remain shared Studio access.
 */
export function rejectLearnerQaAccess(request: NextRequest): NextResponse | null {
  const authorization = request.headers.get("authorization");
  if (contentQaClientTokenMatches(authorization) && !bearerMatches(authorization)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }
  return null;
}

/** @deprecated Use rejectLearnerQaAccess */
export function forbidContentQaOnly(request: NextRequest): NextResponse | null {
  return rejectLearnerQaAccess(request);
}
