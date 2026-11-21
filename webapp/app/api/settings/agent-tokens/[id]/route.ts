import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { requireSignedInStudioAdmin } from "@/lib/generate/access";
import { drizzleAgentTokenStore } from "@/lib/studio-agent-tokens-db";
import { AgentTokenError, revokeStudioAgentToken } from "@/lib/studio-agent-tokens";

export async function DELETE(
  request: NextRequest,
  ctx: { params: Promise<{ id: string }> },
) {
  const denied = await requireSignedInStudioAdmin(request);
  if (denied) return denied;
  const { id } = await ctx.params;
  if (!id) {
    return NextResponse.json({ error: "Missing token id." }, { status: 400 });
  }
  try {
    await revokeStudioAgentToken(drizzleAgentTokenStore, id);
    return NextResponse.json({ ok: true });
  } catch (error) {
    if (error instanceof AgentTokenError) {
      return NextResponse.json({ error: error.message }, { status: 404 });
    }
    return NextResponse.json({ error: "Could not revoke token." }, { status: 500 });
  }
}
