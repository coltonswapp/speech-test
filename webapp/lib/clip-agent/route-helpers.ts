import "server-only";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getToken } from "next-auth/jwt";
import type { z } from "zod";
import { authSecret, studioAgentBearerMatches } from "@/lib/studio-auth";
import { AttemptError } from "@/lib/clip-agent/store";

/** Who made a Studio request: the session email, `agent-token`, or `studio` (auth off locally). */
export async function studioRequester(request: NextRequest): Promise<string> {
  if (await studioAgentBearerMatches(request.headers.get("authorization"))) return "agent-token";
  try {
    const token = await getToken({ req: request, secret: authSecret() });
    if (typeof token?.email === "string") return token.email;
  } catch {
    // fall through
  }
  return "studio";
}

export async function parseBody<T extends z.ZodType>(
  request: NextRequest,
  schema: T,
): Promise<{ data: z.output<T> } | { response: NextResponse }> {
  const parsed = schema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    const where = issue?.path.length ? `${issue.path.join(".")}: ` : "";
    return { response: NextResponse.json({ error: `invalid body (${where}${issue?.message ?? "?"})` }, { status: 400 }) };
  }
  return { data: parsed.data };
}

export function attemptErrorResponse(error: unknown, label: string): NextResponse {
  if (error instanceof AttemptError) {
    return NextResponse.json({ error: error.message }, { status: error.status });
  }
  console.error(`[clip-agent] ${label}`, error);
  return NextResponse.json(
    { error: error instanceof Error ? error.message : "Unexpected error" },
    { status: 500 },
  );
}
