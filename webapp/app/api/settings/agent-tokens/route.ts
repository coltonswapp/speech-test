import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { requireSignedInStudioAdmin } from "@/lib/generate/access";
import { drizzleAgentTokenStore } from "@/lib/studio-agent-tokens-db";
import {
  AgentTokenError,
  createStudioAgentToken,
  listStudioAgentTokens,
} from "@/lib/studio-agent-tokens";

const createSchema = z.object({
  name: z.string().min(1).max(80),
});

export async function GET(request: NextRequest) {
  const denied = await requireSignedInStudioAdmin(request);
  if (denied) return denied;
  try {
    const tokens = (await listStudioAgentTokens(drizzleAgentTokenStore)).map((token) => ({
      ...token,
      createdAt: token.createdAt.toISOString(),
      lastUsedAt: token.lastUsedAt?.toISOString() ?? null,
    }));
    return NextResponse.json({ tokens });
  } catch {
    return NextResponse.json(
      { error: "Could not list tokens. Apply drizzle/0025_studio_agent_tokens.sql if this table is new." },
      { status: 503 },
    );
  }
}

export async function POST(request: NextRequest) {
  const denied = await requireSignedInStudioAdmin(request);
  if (denied) return denied;
  const parsed = createSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: "Name is required (1–80 characters)." }, { status: 400 });
  }
  try {
    const created = await createStudioAgentToken(drizzleAgentTokenStore, parsed.data.name);
    return NextResponse.json(
      {
        token: created.token,
        tokenRecord: {
          ...created.tokenRecord,
          createdAt: created.tokenRecord.createdAt.toISOString(),
          lastUsedAt: created.tokenRecord.lastUsedAt?.toISOString() ?? null,
        },
      },
      { status: 201 },
    );
  } catch (error) {
    if (error instanceof AgentTokenError) {
      const status = error.code === "name_taken" ? 409 : 400;
      return NextResponse.json({ error: error.message }, { status });
    }
    const code = error && typeof error === "object" && "code" in error ? String(error.code) : "";
    if (code === "23505") {
      return NextResponse.json({ error: "An active token with that name already exists." }, { status: 409 });
    }
    return NextResponse.json({ error: "Could not create token." }, { status: 500 });
  }
}
