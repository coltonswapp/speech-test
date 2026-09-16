import { DialogueList } from "@/components/dialogue/dialogue-list";
import { UnitEditor } from "@/components/dialogue/unit-editor";

export default async function DialogueUnitPage({
  params,
}: {
  params: Promise<{ unitId: string }>;
}) {
  const { unitId } = await params;

  return (
    <div className="flex flex-1 gap-6">
      <DialogueList activeId={unitId} scope="unit" />
      <UnitEditor unitId={unitId} />
    </div>
  );
}
