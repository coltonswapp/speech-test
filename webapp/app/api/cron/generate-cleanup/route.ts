import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { cleanupExpiredGenerations } from "@/lib/generate/service";
import { studioGenerateService } from "@/lib/generate/runtime";
import { generateErrorResponse } from "@/lib/generate/http";
import { bearerMatches } from "@/lib/studio-auth";

export async function GET(request: NextRequest) {
  if (!(await bearerMatches(request.headers.get("authorization")))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  try {
    const result = await cleanupExpiredGenerations(studioGenerateService(), {
      limit: 100,
    });
    return NextResponse.json(result);
  } catch (error) {
    return generateErrorResponse(error);
  }
}
