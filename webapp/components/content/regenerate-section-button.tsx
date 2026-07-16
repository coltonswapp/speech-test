"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { SparklesIcon } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { contentApi, type GrammarPoint } from "@/lib/content/client";

type SectionTask = "overview" | "formation" | "usage" | "usageLadders" | "example" | "drills";

const taskLabels: Record<SectionTask, string> = {
  overview: "overview (blurb + forms)",
  formation: "formation blocks",
  usage: "usage blocks",
  usageLadders: "usage ladders",
  example: "a new example",
  drills: "drills",
};

export function RegenerateSectionButton({
  pointId,
  task,
  onGenerated,
}: {
  pointId: string;
  task: SectionTask;
  onGenerated: (point: GrammarPoint) => void;
}) {
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [instructions, setInstructions] = useState("");

  const mutation = useMutation({
    mutationFn: () =>
      contentApi.regenerateSection(pointId, {
        task,
        customInstructions: instructions.trim() || undefined,
      }),
    onSuccess: ({ point }) => {
      onGenerated(point);
      queryClient.invalidateQueries({ queryKey: ["content-point", pointId] });
      toast.success(`Regenerated ${taskLabels[task]}. Review before saving.`);
      setOpen(false);
      setInstructions("");
    },
    onError: (error) => toast.error(error.message),
  });

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <Button
        type="button"
        variant="outline"
        size="sm"
        className="gap-1.5"
        onClick={() => setOpen(true)}
      >
        <SparklesIcon className="size-3.5" />
        Regenerate with AI
      </Button>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Regenerate {taskLabels[task]}</DialogTitle>
          <DialogDescription>
            Uses this point&apos;s current content plus approved gold examples
            as context. Result merges into the draft — save to keep it.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-2">
          <Label>Author instructions (optional)</Label>
          <Textarea
            rows={3}
            placeholder="e.g. focus on casual speech, avoid repeating the train example…"
            value={instructions}
            onChange={(e) => setInstructions(e.target.value)}
            disabled={mutation.isPending}
          />
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            disabled={mutation.isPending}
            onClick={() => setOpen(false)}
          >
            Cancel
          </Button>
          <Button disabled={mutation.isPending} onClick={() => mutation.mutate()}>
            {mutation.isPending ? "Generating…" : "Generate"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
