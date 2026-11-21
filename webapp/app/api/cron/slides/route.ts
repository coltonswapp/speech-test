import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { generateNextDraft } from "@/lib/slides/store";
import { bearerMatches } from "@/lib/studio-auth";

export async function GET(request: NextRequest) {
  if (!(await bearerMatches(request.headers.get("authorization")))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const spotlight = await generateNextDraft("spotlight");
  const decomposition = await generateNextDraft("decomposition");
  return NextResponse.json({
    spotlight,
    decomposition,
  });
}
