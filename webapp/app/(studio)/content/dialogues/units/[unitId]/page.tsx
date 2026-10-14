import { DialogueShell } from "@/components/dialogue/dialogue-shell";
import { UnitEditor } from "@/components/dialogue/unit-editor";

export default async function DialogueUnitPage({
  params,
}: {
  params: Promise<{ unitId: string }>;
}) {
  const { unitId } = await params;

  return (
    <DialogueShell activeId={unitId} scope="unit" collapseSidebarOnMobile>
      <UnitEditor unitId={unitId} />
    </DialogueShell>
  );
}
