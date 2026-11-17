import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { isClientQaAuthorized } from "@/lib/client-auth";
import {
  DOWNLOAD_URL_TTL_SECONDS,
  UPLOAD_URL_TTL_SECONDS,
  feedbackUploadKey,
  signRequestValidationReason,
  uploadSignRequestSchema,
} from "@/lib/feedback-uploads/sign";
import { getSignedDownloadUrl, getSignedUploadUrl } from "@/lib/storage/r2";

function plainText(body: string, status: number) {
  return new NextResponse(body, { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });
}

/**
 * Signs one CSFeedbackKit attachment upload into private R2.
 * Request: `{ id, filename, content_type, size }`.
 * Response: `{ upload_url, download_url, headers, expires_at }`. The app PUTs the bytes
 * to upload_url with the same Content-Type, then sends download_url to its destinations.
 * Auth: same as the other client QA routes (staff ID token, or the DEBUG QA token).
 */
export async function POST(request: NextRequest) {
  if (!(await isClientQaAuthorized(request))) {
    return plainText("missing or invalid bearer token", 401);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return plainText("invalid JSON body", 400);
  }
  const parsed = uploadSignRequestSchema.safeParse(body);
  if (!parsed.success) {
    return plainText(signRequestValidationReason(parsed.error), 400);
  }

  const key = feedbackUploadKey(parsed.data);
  try {
    const [uploadUrl, downloadUrl] = await Promise.all([
      getSignedUploadUrl(key, parsed.data.content_type, UPLOAD_URL_TTL_SECONDS),
      getSignedDownloadUrl(key, DOWNLOAD_URL_TTL_SECONDS),
    ]);
    return NextResponse.json({
      upload_url: uploadUrl,
      download_url: downloadUrl,
      headers: { "Content-Type": parsed.data.content_type },
      expires_at: new Date(Date.now() + DOWNLOAD_URL_TTL_SECONDS * 1000).toISOString(),
    });
  } catch (error) {
    console.error(`[feedback-uploads] ${parsed.data.id}: signing failed`, error);
    return plainText("could not sign upload", 503);
  }
}
