import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { listedClipFacetCounts } from "@/lib/experiments/clips/clip-index";

/**
 * Tag values in use across listed clips, with how many clips carry each, most
 * first: `{ facets: { format: [{ value: "vlog", count: 22 }, …], topic: […],
 * register, speakers, dialect, pace, series } }`. For building filter chips;
 * pass a value back to /api/public/clips as `?<facet>=<value>`.
 *
 * `?feed=1` counts feed clips only.
 */
export async function GET(request: NextRequest) {
  const feedOnly = ["1", "true"].includes(request.nextUrl.searchParams.get("feed") ?? "");
  try {
    const facets = await listedClipFacetCounts(feedOnly);
    return NextResponse.json({ facets }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    console.error("[public/clips/facets]", error);
    return NextResponse.json({ error: "Couldn’t count clip tags." }, { status: 500 });
  }
}
