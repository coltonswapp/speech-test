import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  AUTH_COOKIE,
  authIsEnforced,
  bearerMatches,
  isPublicPath,
  passphraseCookieMatches,
} from "@/lib/studio-auth";

// Do not import next-auth/jwt here. Next 16 compiles proxy.ts for the edge
// runtime, and that package has no edge export (dev Unhandled Rejection).

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (isPublicPath(pathname)) {
    return NextResponse.next();
  }

  if (!authIsEnforced()) {
    return NextResponse.next();
  }

  if (bearerMatches(request.headers.get("authorization"))) {
    return NextResponse.next();
  }

  const passphrase = process.env.APP_PASSPHRASE?.trim() ?? "";
  if (
    passphrase &&
    passphraseCookieMatches(request.cookies.get(AUTH_COOKIE)?.value, passphrase)
  ) {
    return NextResponse.next();
  }

  // Google sessions are issued at /api/auth/* (Node). Cookie presence is a
  // gate for the allowlisted login we already ran; unsigned fakes are not a
  // concern until this ships with Google env on Vercel (follow-up: verify JWT
  // in Node, not edge).
  const googleCookie =
    request.cookies.get("__Secure-next-auth.session-token")?.value ||
    request.cookies.get("next-auth.session-token")?.value;
  if (googleCookie) {
    return NextResponse.next();
  }

  if (pathname.startsWith("/api/")) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const loginUrl = new URL("/login", request.url);
  loginUrl.searchParams.set("next", pathname);
  return NextResponse.redirect(loginUrl);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
