import "server-only";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db/client";
import { appSettings } from "@/lib/db/schema";
import { configuredAgentTargets } from "@/lib/clip-agent/dispatch";
import { CLIP_AGENT_TARGETS } from "@/lib/clip-agent/schema";

const key = "content-issue-agents";
export const routingSchema = z.object({
  enabled: z.array(z.enum([...CLIP_AGENT_TARGETS, "hana"])),
  clip: z.enum(CLIP_AGENT_TARGETS).nullable(),
  scene: z.literal("hana").nullable(),
});
export type Routing = z.infer<typeof routingSchema>;

export async function agentSettings() {
  const connected = [...configuredAgentTargets(), ...(process.env.HANA_ISSUES_WEBHOOK_URL && process.env.HANA_ISSUES_WEBHOOK_SECRET ? ["hana" as const] : [])];
  const [row] = await db.select().from(appSettings).where(eq(appSettings.key, key));
  const routing: Routing = row ? routingSchema.parse(row.value) : {
    enabled: [...CLIP_AGENT_TARGETS, "hana"], clip: configuredAgentTargets()[0] ?? null, scene: "hana",
  };
  const clips = configuredAgentTargets().filter(agent => routing.enabled.includes(agent));
  clips.sort((a,b) => Number(b === routing.clip) - Number(a === routing.clip));
  return { routing, connected, clips, hana: connected.includes("hana") && routing.enabled.includes("hana") && routing.scene === "hana" };
}

export async function saveRouting(value: Routing) {
  const routing = routingSchema.parse(value);
  await db.insert(appSettings).values({key, value: routing}).onConflictDoUpdate({target: appSettings.key, set: {value: routing}});
}
