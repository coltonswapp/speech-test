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

const storedRouting = z.object({
  enabled: z.array(z.unknown()).optional().catch(undefined),
  clip: routingSchema.shape.clip.optional().catch(null),
  scene: routingSchema.shape.scene.optional().catch(null),
});

export async function agentSettings() {
  const connected = [...configuredAgentTargets(), ...(process.env.HANA_ISSUES_WEBHOOK_URL && process.env.HANA_ISSUES_WEBHOOK_SECRET ? ["hana" as const] : [])];
  const [row] = await db.select().from(appSettings).where(eq(appSettings.key, key));
  const saved = storedRouting.safeParse(row?.value).data;
  const known = [...CLIP_AGENT_TARGETS, "hana"] as const;
  const enabled = saved?.enabled;
  const routing: Routing = {
    enabled: enabled ? known.filter(agent => enabled.includes(agent)) : [...known],
    clip: saved?.clip === undefined ? configuredAgentTargets()[0] ?? null : saved.clip,
    scene: saved?.scene === undefined ? "hana" : saved.scene,
  };
  const clips = configuredAgentTargets().filter(agent => routing.enabled.includes(agent));
  clips.sort((a,b) => Number(b === routing.clip) - Number(a === routing.clip));
  return { routing, connected, clips, hana: connected.includes("hana") && routing.enabled.includes("hana") && routing.scene === "hana" };
}

export async function saveRouting(value: Routing) {
  const routing = routingSchema.parse(value);
  await db.insert(appSettings).values({key, value: routing}).onConflictDoUpdate({target: appSettings.key, set: {value: routing}});
}
