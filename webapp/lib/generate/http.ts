import { NextResponse } from "next/server";
import { GenerateUserError } from "./validate";
import { GeminiTTSError } from "@/lib/tts/gemini-tts";

export {
  forbidContentQaOnly,
  rejectLearnerQaAccess,
  requireGenerateAccess,
} from "./access";

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
          "Could not reach the Generate library. If this environment is new, apply drizzle/0020_tts_generation.sql, drizzle/0021_tts_generation_lifecycle.sql, then drizzle/0022_tts_generation_revision.sql.",
      },
      { status: 503 },
    );
  }
  return NextResponse.json({ error: message }, { status: 500 });
}
