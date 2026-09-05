import { DialogueShell } from "@/components/dialogue/dialogue-shell";

export default function DialoguesPage() {
  return (
    <DialogueShell>
      <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
        Select a dialogue collection or scenario to view or edit it.
      </div>
    </DialogueShell>
  );
}
