import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { cleanupExpiredGenerations } from "@/lib/generate/service";
import { studioGenerateService } from "@/lib/generate/runtime";
import { generateErrorResponse } from "@/lib/generate/http";

function authorized(request: NextRequest): boolean {
  const header = request.headers.get("authorization");
  const token = header?.startsWith("Bearer ") ? header.slice(7).trim() : "";
  const secrets = [
    process.env.CRON_SECRET?.trim(),
    process.env.STUDIO_AGENT_TOKEN?.trim(),
  ].filter(Boolean);
  return Boolean(token && secrets.includes(token));
}

export async function GET(request: NextRequest) {
  if (!authorized(request)) {
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
