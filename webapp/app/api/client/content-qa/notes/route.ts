import type { NextRequest } from "next/server";
import { isClientQaAuthorized } from "@/lib/client-auth";
import { handleNotePost } from "@/lib/shizen-notes/handler";

/**
 * QA notes from the learner client. Same contract as /hooks/shizen-note.
 * Auth: Firebase staff ID token (Release) or CONTENT_QA_CLIENT_TOKEN (DEBUG);
 * see lib/client-auth.ts. The webhook token stays server-side.
 */
export async function POST(request: NextRequest) {
  return handleNotePost(request, isClientQaAuthorized);
}
