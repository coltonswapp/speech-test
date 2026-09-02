import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getToken } from "next-auth/jwt";
import {
  AUTH_COOKIE,
  authIsEnforced,
  authSecret,
  bearerMatches,
  isEmailAllowed,
  isGoogleAuthConfigured,
  isPublicPath,
  passphraseCookieMatches,
} from "@/lib/studio-auth";

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

  if (isGoogleAuthConfigured()) {
    const token = await getToken({
      req: request,
      secret: authSecret(),
    });
    if (isEmailAllowed(typeof token?.email === "string" ? token.email : null)) {
      return NextResponse.next();
    }
  }

  const passphrase = process.env.APP_PASSPHRASE?.trim() ?? "";
  if (
    passphrase &&
    passphraseCookieMatches(request.cookies.get(AUTH_COOKIE)?.value, passphrase)
  ) {
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
