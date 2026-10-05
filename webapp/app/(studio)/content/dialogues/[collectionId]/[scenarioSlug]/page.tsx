import { Suspense } from "react";
import { DialogueShell } from "@/components/dialogue/dialogue-shell";
import { ScenarioEditor } from "@/components/dialogue/scenario-editor";
import { Skeleton } from "@/components/ui/skeleton";

function ScenarioEditorFallback() {
  return (
    <div className="flex flex-1 flex-col gap-4">
      <Skeleton className="h-8 w-64" />
      <Skeleton className="h-48 w-full" />
    </div>
  );
}

export default async function DialogueScenarioPage({
  params,
}: {
  params: Promise<{ collectionId: string; scenarioSlug: string }>;
}) {
  const { collectionId, scenarioSlug } = await params;

  return (
    <DialogueShell
      activeId={`${collectionId}/${scenarioSlug}`}
      scope="unit"
      collapseSidebarOnMobile
    >
      <Suspense fallback={<ScenarioEditorFallback />}>
        <ScenarioEditor
          collectionId={collectionId}
          scenarioSlug={scenarioSlug}
        />
      </Suspense>
    </DialogueShell>
  );
}
