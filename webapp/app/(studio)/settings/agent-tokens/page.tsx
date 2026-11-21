import { AgentTokensPanel, type AgentTokenListItem } from "@/components/settings/agent-tokens-panel";
import { drizzleAgentTokenStore } from "@/lib/studio-agent-tokens-db";
import { listStudioAgentTokens } from "@/lib/studio-agent-tokens";

export const dynamic = "force-dynamic";

function toListItem(token: {
  id: string;
  name: string;
  prefix: string;
  createdAt: Date;
  lastUsedAt: Date | null;
}): AgentTokenListItem {
  return {
    id: token.id,
    name: token.name,
    prefix: token.prefix,
    createdAt: token.createdAt.toISOString(),
    lastUsedAt: token.lastUsedAt?.toISOString() ?? null,
  };
}

export default async function AgentTokensPage() {
  let tokens: AgentTokenListItem[] = [];
  let loadError: string | null = null;
  try {
    tokens = (await listStudioAgentTokens(drizzleAgentTokenStore)).map(toListItem);
  } catch {
    loadError =
      "Could not load tokens. Apply webapp/drizzle/0025_studio_agent_tokens.sql if this table is new.";
  }

  return <AgentTokensPanel tokens={tokens} loadError={loadError} />;
}
