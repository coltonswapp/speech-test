import "server-only";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { acceptNote } from "./accept";
import { noteValidationReason, shizenNoteSchema } from "./schema";

function plainText(body: string, status: number) {
  return new NextResponse(body, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}

/**
 * Shared POST handler for the note endpoints. Auth runs before the body is
 * read; errors are plain text, success is 202 `{ job_id }`.
 */
export async function handleNotePost(
  request: NextRequest,
  tokenMatches: (header: string | null) => boolean,
) {
  if (!tokenMatches(request.headers.get("authorization"))) {
    return plainText("missing or invalid bearer token", 401);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return plainText("invalid JSON body", 400);
  }

  const parsed = shizenNoteSchema.safeParse(body);
  if (!parsed.success) {
    return plainText(noteValidationReason(parsed.error, body), 400);
  }

  const jobId = await acceptNote(parsed.data);
  return NextResponse.json({ job_id: jobId }, { status: 202 });
}
