import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { AUTH_COOKIE } from "@/lib/studio-auth";

export async function GET(request: NextRequest) {
  const login = new URL("/api/auth/signout", request.url);
  login.searchParams.set("callbackUrl", "/login");
  const response = NextResponse.redirect(login, { status: 303 });
  response.cookies.set(AUTH_COOKIE, "", {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });
  return response;
}
