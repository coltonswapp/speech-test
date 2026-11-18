import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import {
  clipFeedbackCounts,
  listClipFeedback,
  openClipIssueCount,
  setClipFeedbackStatus,
} from "@/lib/clip-feedback/admin";
import { CLIP_FEEDBACK_REASONS, CLIP_FEEDBACK_STATUSES } from "@/lib/clip-feedback/schema";

const listQuery = z.object({
  clip_id: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/).optional(),
  status: z.enum([...CLIP_FEEDBACK_STATUSES, "issues", "all"]).optional(),
  reason: z.enum(CLIP_FEEDBACK_REASONS).optional(),
});

/**
 * Learner clip feedback for Studio. `?clip_id=` narrows to one clip and adds
 * its thumbs totals; `?status=` is open | resolved | wontfix | duplicate |
 * issues (default: anything with a status) | all (plain ratings too);
 * `?reason=` filters by reason. Always returns the open issue count.
 */
export async function GET(request: NextRequest) {
  const parsed = listQuery.safeParse(Object.fromEntries(request.nextUrl.searchParams));
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid query" }, { status: 400 });
  }
  const { clip_id: clipId, status, reason } = parsed.data;
  try {
    const [rows, counts, openIssues] = await Promise.all([
      listClipFeedback({ clipId, status, reason }),
      clipId ? clipFeedbackCounts(clipId) : null,
      openClipIssueCount(),
    ]);
    return NextResponse.json(
      { rows, counts, openIssues },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  } catch (error) {
    console.error("[experiments/clip-feedback]", error);
    return NextResponse.json({ error: "could not load feedback" }, { status: 500 });
  }
}

const patchBody = z.object({
  id: z.string().min(1).max(64),
  status: z.enum(CLIP_FEEDBACK_STATUSES),
  note: z.string().trim().max(1_000).optional(),
});

/** Triage one issue: resolved | wontfix | duplicate, or open to reopen it. */
export async function PATCH(request: NextRequest) {
  const parsed = patchBody.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: "body needs id and status" }, { status: 400 });
  }
  const { id, status, note } = parsed.data;
  try {
    const ok = await setClipFeedbackStatus(id, status, note || null);
    if (!ok) return NextResponse.json({ error: "issue not found" }, { status: 404 });
    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("[experiments/clip-feedback]", error);
    return NextResponse.json({ error: "could not update" }, { status: 500 });
  }
}
