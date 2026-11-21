import { revalidatePath } from "next/cache";
import { agentSettings, routingSchema, saveRouting } from "@/lib/content-issues/agents";
import { CLIP_AGENT_TARGET_LABELS, CLIP_AGENT_TARGETS } from "@/lib/clip-agent/schema";

export const dynamic = "force-dynamic";

export default async function AgentsPage() {
  const {routing, connected} = await agentSettings();
  async function save(form: FormData) {
    "use server";
    await saveRouting(routingSchema.parse({ enabled: form.getAll("enabled"), clip: form.get("clip") || null, scene: form.get("scene") || null }));
    revalidatePath("/settings/agents");
  }
  return <form action={save} className="max-w-xl space-y-6">
    <h1 className="text-2xl font-semibold">Agents</h1>
    <fieldset className="space-y-2"><legend className="font-medium">Available for manual dispatch</legend>
    {([...CLIP_AGENT_TARGETS, "hana"] as const).map(agent => <label key={agent} className="flex items-center gap-3">
      <input type="checkbox" name="enabled" value={agent} defaultChecked={routing.enabled.includes(agent)}/>
      {agent === "hana" ? "Hana · Scenes" : CLIP_AGENT_TARGET_LABELS[agent] + " · Clips"}
      <span className="text-muted-foreground">{connected.includes(agent) ? "Configured" : "Missing credentials"}</span>
    </label>)}</fieldset>
    <label className="block">Preferred clip agent <select className="border p-1" name="clip" defaultValue={routing.clip ?? ""}><option value="">First available</option>{CLIP_AGENT_TARGETS.map(agent => <option key={agent} value={agent}>{CLIP_AGENT_TARGET_LABELS[agent]}</option>)}</select></label>
    <label className="block">Scene agent <select className="border p-1" name="scene" defaultValue={routing.scene ?? ""}><option value="">Unassigned</option><option value="hana">Hana</option></select></label>
    <button className="rounded border px-3 py-2">Save settings</button>
  </form>;
}
