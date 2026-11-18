import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { requireClientLearner } from "@/lib/client-auth";
import { clipFeedbackRequestSchema, feedbackValidationReason } from "@/lib/clip-feedback/schema";
import { saveClipFeedback } from "@/lib/clip-feedback/store";

const CLIP_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;

/**
 * A learner's thumbs rating on a clip, or a reported issue on the clip or one
 * of its lines. Body: see clipFeedbackRequestSchema.
 * Response: `{ id, status }` (status null for a plain rating).
 * Auth: any signed-in learner (Firebase ID token); see requireClientLearner.
 */
export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const learner = await requireClientLearner(request);
  if (learner instanceof NextResponse) return learner;

  const { id: clipId } = await params;
  if (!CLIP_ID.test(clipId)) {
    return NextResponse.json({ error: "invalid clip id" }, { status: 400 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid JSON body" }, { status: 400 });
  }
  const parsed = clipFeedbackRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: feedbackValidationReason(parsed.error) }, { status: 400 });
  }

  try {
    const result = await saveClipFeedback(learner.uid, clipId, parsed.data);
    if (!result.ok) {
      return result.error === "unknown_clip"
        ? NextResponse.json({ error: "clip not found" }, { status: 404 })
        : NextResponse.json({ error: "too much feedback today, try again tomorrow" }, { status: 429 });
    }
    return NextResponse.json({ id: result.id, status: result.status }, { status: 201 });
  } catch (error) {
    console.error(`[clip-feedback] ${clipId}: save failed`, error);
    return NextResponse.json({ error: "could not save feedback" }, { status: 503 });
  }
}
