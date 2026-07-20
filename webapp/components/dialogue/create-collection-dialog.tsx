"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { dialogueApi, type UnitSummary } from "@/lib/dialogue/client";
import { CollectionTemplatePicker } from "@/components/dialogue/collection-template-picker";

export function CreateCollectionDialog({
  open,
  onOpenChange,
  units,
  defaultUnitId = "",
  lockUnit = false,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  units: UnitSummary[];
  /** Unit the new collection is filed under. */
  defaultUnitId?: string;
  /** Hide the unit picker and always use defaultUnitId — for creating a lesson from within a unit page. */
  lockUnit?: boolean;
}) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [newId, setNewId] = useState("");
  const [newTitle, setNewTitle] = useState("");
  const [newSubtitle, setNewSubtitle] = useState("");
  const [newSceneImage, setNewSceneImage] = useState("");
  const [newUnitId, setNewUnitId] = useState(defaultUnitId);

  function reset() {
    setNewId("");
    setNewTitle("");
    setNewSubtitle("");
    setNewSceneImage("");
    setNewUnitId(defaultUnitId);
  }

  const createMutation = useMutation({
    mutationFn: () =>
      dialogueApi.createCollection({
        id: newId.trim(),
        title: newTitle.trim(),
        subtitle: newSubtitle.trim() || undefined,
        sceneImage: newSceneImage.trim() || undefined,
        unitId: newUnitId || undefined,
      }),
    onSuccess: ({ collection }) => {
      queryClient.invalidateQueries({ queryKey: ["dialogue-collections"] });
      queryClient.invalidateQueries({ queryKey: ["curriculum-units"] });
      onOpenChange(false);
      reset();
      toast.success(`Collection "${collection.title}" created.`);
      router.push(`/content/dialogues/${collection.id}`);
    },
    onError: (error) => toast.error(error.message),
  });

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        onOpenChange(next);
        if (!next) reset();
        else setNewUnitId(defaultUnitId);
      }}
    >
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>New dialogue collection</DialogTitle>
        </DialogHeader>
        <div className="flex flex-col gap-4">
          <div className="flex flex-col gap-2">
            <Label className="text-xs text-muted-foreground">Quick start</Label>
            <CollectionTemplatePicker
              onSelect={(template) => {
                setNewId(template.collectionId);
                setNewTitle(template.collectionTitle);
                setNewSubtitle(template.collectionSubtitle ?? "");
                setNewSceneImage(template.sceneImage ?? "");
              }}
            />
          </div>

          <div className="flex flex-col gap-3 border-t border-border/60 pt-4">
            <div className="flex flex-col gap-2">
              <Label>ID (slug, immutable)</Label>
              <Input
                value={newId}
                onChange={(e) => setNewId(e.target.value)}
                placeholder="train-station"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label>Title</Label>
              <Input
                value={newTitle}
                onChange={(e) => setNewTitle(e.target.value)}
                placeholder="At the Train Station"
              />
            </div>
            {!lockUnit && units.length > 0 && (
              <div className="flex flex-col gap-2">
                <Label>Unit</Label>
                <Select
                  value={newUnitId}
                  onValueChange={(value) => setNewUnitId(value ?? "")}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Unfiled" />
                  </SelectTrigger>
                  <SelectContent>
                    {units.map((unit) => (
                      <SelectItem key={unit.id} value={unit.id}>
                        {unit.title} (N{unit.jlptLevel})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}
            <Button
              onClick={() => createMutation.mutate()}
              disabled={
                createMutation.isPending || !newId.trim() || !newTitle.trim()
              }
            >
              Create
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
