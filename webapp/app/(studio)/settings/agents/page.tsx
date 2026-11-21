import { revalidatePath } from "next/cache";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { agentSettings, routingSchema, saveRouting } from "@/lib/content-issues/agents";
import { CLIP_AGENT_TARGET_LABELS, CLIP_AGENT_TARGETS } from "@/lib/clip-agent/schema";

export const dynamic = "force-dynamic";

const clipOptions = [
  { value: "none", label: "First available" },
  ...CLIP_AGENT_TARGETS.map(value => ({ value, label: CLIP_AGENT_TARGET_LABELS[value] })),
];
const sceneOptions = [{ value: "none", label: "Unassigned" }, { value: "hana", label: "Hana" }];

export default async function AgentsPage() {
  const { routing, connected } = await agentSettings();
  async function save(form: FormData) {
    "use server";
    const clip = form.get("clip");
    const scene = form.get("scene");
    await saveRouting(routingSchema.parse({
      enabled: form.getAll("enabled"),
      clip: clip === "none" ? null : clip,
      scene: scene === "none" ? null : scene,
    }));
    revalidatePath("/settings/agents");
  }

  return (
    <form action={save} className="flex flex-col gap-6">
      <Card>
        <CardHeader><CardTitle role="heading" aria-level={2} className="text-base font-medium">Available for manual dispatch</CardTitle></CardHeader>
        <CardContent className="flex flex-col gap-3">
          {([...CLIP_AGENT_TARGETS, "hana"] as const).map(agent => (
            <div key={agent} className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-border/60 px-4 py-3">
              <Label htmlFor={agent} className="text-sm font-medium">
                {agent === "hana" ? "Hana · Scenes" : CLIP_AGENT_TARGET_LABELS[agent] + " · Clips"}
              </Label>
              <div className="flex items-center gap-3">
                <Badge variant={connected.includes(agent) ? "default" : "destructive"}>
                  {connected.includes(agent) ? "Configured" : "Missing credentials"}
                </Badge>
                <Switch id={agent} name="enabled" value={agent} defaultChecked={routing.enabled.includes(agent)} />
              </div>
            </div>
          ))}
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle role="heading" aria-level={2} className="text-base font-medium">Default agents</CardTitle></CardHeader>
        <CardContent className="flex flex-col gap-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <Label htmlFor="clip-agent">Preferred clip agent</Label>
            <Select name="clip" items={clipOptions} defaultValue={routing.clip ?? "none"}>
              <SelectTrigger id="clip-agent"><SelectValue /></SelectTrigger>
              <SelectContent>{clipOptions.map(option => <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="flex flex-wrap items-center justify-between gap-2">
            <Label htmlFor="scene-agent">Scene agent</Label>
            <Select name="scene" items={sceneOptions} defaultValue={routing.scene ?? "none"}>
              <SelectTrigger id="scene-agent"><SelectValue /></SelectTrigger>
              <SelectContent>{sceneOptions.map(option => <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>)}</SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>
      <Button type="submit" size="sm" className="self-start">Save settings</Button>
    </form>
  );
}
