import { DialogueShell } from "@/components/dialogue/dialogue-shell";
import { CollectionEditor } from "@/components/dialogue/collection-editor";

export default async function DialogueCollectionPage({
  params,
}: {
  params: Promise<{ collectionId: string }>;
}) {
  const { collectionId } = await params;

  return (
    <DialogueShell activeId={collectionId} collapseSidebarOnMobile>
      <CollectionEditor collectionId={collectionId} />
    </DialogueShell>
  );
}
