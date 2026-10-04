import type { NextRequest } from "next/server";
import { handleNotePost } from "@/lib/shizen-notes/handler";
import { contentQaClientTokenMatches } from "@/lib/studio-auth";

/**
 * QA notes from the learner client. Same contract as /hooks/shizen-note,
 * authed with Bearer CONTENT_QA_CLIENT_TOKEN so the webhook token stays server-side.
 */
export async function POST(request: NextRequest) {
  return handleNotePost(request, contentQaClientTokenMatches);
}
