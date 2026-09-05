import { DialogueShell } from "@/components/dialogue/dialogue-shell";
import { ScenarioEditor } from "@/components/dialogue/scenario-editor";

export default async function DialogueScenarioPage({
  params,
}: {
  params: Promise<{ collectionId: string; scenarioSlug: string }>;
}) {
  const { collectionId, scenarioSlug } = await params;

  return (
    <DialogueShell
      activeId={`${collectionId}/${scenarioSlug}`}
      collapseSidebarOnMobile
    >
      <ScenarioEditor collectionId={collectionId} scenarioSlug={scenarioSlug} />
    </DialogueShell>
  );
}
