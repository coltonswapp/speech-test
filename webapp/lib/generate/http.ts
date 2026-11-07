import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { bearerMatches, contentQaClientTokenMatches } from "@/lib/studio-auth";
import { GenerateUserError } from "./validate";
import { GeminiTTSError } from "@/lib/tts/gemini-tts";

export function forbidContentQaOnly(request: NextRequest): NextResponse | null {
  const authorization = request.headers.get("authorization");
  if (contentQaClientTokenMatches(authorization) && !bearerMatches(authorization)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }
  return null;
}

export function generateErrorResponse(error: unknown): NextResponse {
  if (error instanceof GenerateUserError) {
    return NextResponse.json({ error: error.message }, { status: error.status });
  }
  if (error instanceof GeminiTTSError) {
    const quota = /quota/i.test(error.message);
    return NextResponse.json(
      { error: error.message },
      { status: quota ? 429 : 502 },
    );
  }
  const message = error instanceof Error ? error.message : "Unexpected error.";
  if (/Failed query|relation .* does not exist|ECONNREFUSED|DATABASE_URL/i.test(message)) {
    return NextResponse.json(
      {
        error:
          "Could not reach the Generate library. If this environment is new, apply drizzle/0020_tts_generation.sql.",
      },
      { status: 503 },
    );
  }
  return NextResponse.json({ error: message }, { status: 500 });
}
