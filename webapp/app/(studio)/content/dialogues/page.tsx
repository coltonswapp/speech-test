import { DialogueList } from "@/components/dialogue/dialogue-list";

export default function DialoguesPage() {
  return (
    <div className="flex flex-1 gap-6">
      <DialogueList />
      <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
        Select a dialogue collection or scenario to view or edit it.
      </div>
    </div>
  );
}
