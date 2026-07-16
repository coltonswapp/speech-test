import { DialogueList } from "@/components/dialogue/dialogue-list";
import { ScenarioEditor } from "@/components/dialogue/scenario-editor";

export default async function DialogueScenarioPage({
  params,
}: {
  params: Promise<{ collectionId: string; scenarioSlug: string }>;
}) {
  const { collectionId, scenarioSlug } = await params;

  return (
    <div className="flex flex-1 gap-6">
      <DialogueList activeId={`${collectionId}/${scenarioSlug}`} />
      <ScenarioEditor collectionId={collectionId} scenarioSlug={scenarioSlug} />
    </div>
  );
}
