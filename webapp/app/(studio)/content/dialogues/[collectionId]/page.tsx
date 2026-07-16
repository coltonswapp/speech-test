import { DialogueList } from "@/components/dialogue/dialogue-list";
import { CollectionEditor } from "@/components/dialogue/collection-editor";

export default async function DialogueCollectionPage({
  params,
}: {
  params: Promise<{ collectionId: string }>;
}) {
  const { collectionId } = await params;

  return (
    <div className="flex flex-1 gap-6">
      <DialogueList activeId={collectionId} />
      <CollectionEditor collectionId={collectionId} />
    </div>
  );
}
