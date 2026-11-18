import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { listedClipFacetCounts } from "@/lib/experiments/clips/clip-index";

/**
 * Tag values in use across listed clips, with how many clips carry each, most
 * first: `{ facets: { format: [{ value: "vlog", count: 22 }, …], topic: […],
 * register, speakers, dialect, pace, series } }`. For building filter chips;
 * pass a value back to /api/public/clips as `?<facet>=<value>`.
 *
 * `?feed=1` counts feed clips only. `?jlpt=3` counts only clips rated exactly
 * that level (N3), matching /api/public/clips?jlpt=3.
 */
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const feedOnly = ["1", "true"].includes(params.get("feed") ?? "");
  const jlptParam = params.get("jlpt");
  const jlpt = jlptParam === null ? null : Number(jlptParam);
  if (jlpt !== null && !(Number.isInteger(jlpt) && jlpt >= 1 && jlpt <= 5)) {
    return NextResponse.json({ error: "jlpt must be 1 (N1) to 5 (N5)." }, { status: 400 });
  }
  try {
    const facets = await listedClipFacetCounts(feedOnly, jlpt);
    return NextResponse.json({ facets }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    console.error("[public/clips/facets]", error);
    return NextResponse.json({ error: "Couldn’t count clip tags." }, { status: 500 });
  }
}
