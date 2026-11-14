import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { db } from "@/lib/db/client";
import { buildClipPayload, clipReferencedPatternIds } from "@/lib/experiments/clips/payload";
import { fetchExportedTeachingPatterns } from "@/lib/patterns/export";
import { isValidClipId, readClipDraft } from "@/lib/experiments/clips/store";

/**
 * Word-synced clip payload, built live from the Studio draft: a clip is
 * available as soon as it is aligned, and transcript edits show up on the
 * next fetch. 404 until every token has a timestamp. A deprecated clip is
 * still served (with `deprecated` set) so saved items that point at it keep
 * their transcript; it just no longer appears in the list.
 */
export async function GET(
  _request: NextRequest,
  ctx: RouteContext<"/api/public/clips/[id]">
) {
  const { id } = await ctx.params;
  if (!isValidClipId(id)) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  const draft = await readClipDraft(id);
  const patterns = draft
    ? await fetchExportedTeachingPatterns(db, clipReferencedPatternIds(draft))
    : [];
  const payload = draft ? buildClipPayload(draft, patterns) : null;
  if (!payload) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json(payload, {
    headers: { "Cache-Control": "private, no-store" },
  });
}
