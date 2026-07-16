import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getAppPassphrase } from "@/lib/secrets";

const AUTH_COOKIE = "studio_auth";

export async function POST(request: NextRequest) {
  const form = await request.formData();
  const passphrase = String(form.get("passphrase") ?? "");
  const next = String(form.get("next") ?? "/");

  const expected = getAppPassphrase();
  if (!expected || passphrase !== expected) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("next", next);
    loginUrl.searchParams.set("error", "1");
    return NextResponse.redirect(loginUrl, { status: 303 });
  }

  const response = NextResponse.redirect(new URL(next, request.url), {
    status: 303,
  });
  response.cookies.set(AUTH_COOKIE, expected, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 30,
  });
  return response;
}
