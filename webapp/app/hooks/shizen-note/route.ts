import type { NextRequest } from "next/server";
import { handleNotePost } from "@/lib/shizen-notes/handler";
import { shizenNoteWebhookTokenMatches } from "@/lib/studio-auth";

/**
 * Shizen note webhook for non-app callers (Studio, MCP, scripts).
 * Auth: Bearer SHIZEN_NOTE_WEBHOOK_TOKEN, checked before the body is read.
 * Accepted notes return 202 `{ job_id }` and are delivered to Shohei.
 */
export async function POST(request: NextRequest) {
  return handleNotePost(request, shizenNoteWebhookTokenMatches);
}
