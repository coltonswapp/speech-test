import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export async function GET(request: NextRequest) {
  const login = new URL("/api/auth/signout", request.url);
  login.searchParams.set("callbackUrl", "/login");
  const response = NextResponse.redirect(login, { status: 303 });
  // Clear the retired passphrase cookie too.
  response.cookies.delete("studio_auth");
  return response;
}
