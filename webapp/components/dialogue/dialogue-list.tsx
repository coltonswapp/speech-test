"use client";

import { useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  useMutation,
  useQueries,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { toast } from "sonner";
import { FileJson, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { dialogueApi, scenarioSlug } from "@/lib/dialogue/client";
import { SectionSwitcher } from "@/components/content/section-switcher";
import { CollectionTemplatePicker } from "@/components/dialogue/collection-template-picker";

export function DialogueList({ activeId }: { activeId?: string }) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const importInputRef = useRef<HTMLInputElement>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [newId, setNewId] = useState("");
  const [newTitle, setNewTitle] = useState("");
  const [newSubtitle, setNewSubtitle] = useState("");
  const [newSceneImage, setNewSceneImage] = useState("");

  const { data, isLoading } = useQuery({
    queryKey: ["dialogue-collections"],
    queryFn: dialogueApi.listCollections,
  });

  const createMutation = useMutation({
    mutationFn: () =>
      dialogueApi.createCollection({
        id: newId.trim(),
        title: newTitle.trim(),
        subtitle: newSubtitle.trim() || undefined,
        sceneImage: newSceneImage.trim() || undefined,
      }),
    onSuccess: ({ collection }) => {
      queryClient.invalidateQueries({ queryKey: ["dialogue-collections"] });
      setCreateOpen(false);
      setNewId("");
      setNewTitle("");
      setNewSubtitle("");
      setNewSceneImage("");
      toast.success(`Collection "${collection.title}" created.`);
      router.push(`/content/dialogues/${collection.id}`);
    },
    onError: (error) => toast.error(error.message),
  });

  const importMutation = useMutation({
    mutationFn: (file: File) => dialogueApi.importCollection(file),
    onSuccess: ({ collectionId, scenarioCount, title }) => {
      queryClient.invalidateQueries({ queryKey: ["dialogue-collections"] });
      queryClient.invalidateQueries({ queryKey: ["dialogue-collection"] });
      queryClient.invalidateQueries({ queryKey: ["dialogue-scenario"] });
      toast.success(`Imported "${title}" — ${scenarioCount} scenarios.`);
      router.push(`/content/dialogues/${collectionId}`);
    },
    onError: (error) => toast.error(error.message),
  });

  const collections = data?.collections ?? [];

  const audioStatusQueries = useQueries({
    queries: collections.map((collection) => ({
      queryKey: ["dialogue-collection-audio-status", collection.id],
      queryFn: () => dialogueApi.audioStatus(collection.id),
    })),
  });
  const audioStatusById = new Map(
    audioStatusQueries.flatMap(
      (query) => query.data?.scenarios.map((s) => [s.id, s] as const) ?? []
    )
  );

  return (
    <div className="flex w-80 shrink-0 flex-col gap-3 border-r border-border/60 pr-4">
      <SectionSwitcher active="dialogues" />

      <Button
        size="sm"
        className="w-full justify-start gap-2"
        onClick={() => setCreateOpen(true)}
      >
        <Plus className="size-4" />
        New collection
      </Button>
      <Button
        size="sm"
        variant="outline"
        className="w-full justify-start gap-2"
        onClick={() => importInputRef.current?.click()}
        disabled={importMutation.isPending}
      >
        <FileJson className="size-4" />
        {importMutation.isPending ? "Importing…" : "Import collection JSON"}
      </Button>
      <input
        ref={importInputRef}
        type="file"
        accept=".json"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) importMutation.mutate(file);
          e.target.value = "";
        }}
      />

      <ScrollArea className="flex-1">
        <div className="flex flex-col gap-4">
          {isLoading &&
            Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-24 w-full rounded-md" />
            ))}

          {!isLoading && collections.length === 0 && (
            <p className="px-2 py-4 text-sm text-muted-foreground">
              No dialogue collections yet. Create one or import a collection
              JSON.
            </p>
          )}

          {collections.map((collection) => (
            <div key={collection.id} className="flex flex-col gap-1">
              <Link
                href={`/content/dialogues/${collection.id}`}
                className={cn(
                  "flex flex-col rounded-md px-3 py-2 text-sm transition-colors",
                  collection.id === activeId
                    ? "bg-accent text-accent-foreground"
                    : "hover:bg-accent/50"
                )}
              >
                <span className="truncate font-medium">{collection.title}</span>
                <span className="truncate text-xs text-muted-foreground">
                  {collection.id} · {collection.scenarios.length} scenarios
                </span>
              </Link>
              {collection.scenarios.map((scenario) => (
                <Link
                  key={scenario.id}
                  href={`/content/dialogues/${collection.id}/${scenarioSlug(scenario)}`}
                  className={cn(
                    "ml-3 flex items-center justify-between gap-2 rounded-md px-3 py-1.5 text-sm transition-colors",
                    scenario.id === activeId
                      ? "bg-accent text-accent-foreground"
                      : "hover:bg-accent/50"
                  )}
                >
                  <span className="truncate">{scenario.menuTitle}</span>
                  {(() => {
                    const status = audioStatusById.get(scenario.id);
                    if (!status?.hasSelectedTake) {
                      return (
                        <span className="shrink-0 text-xs text-muted-foreground">
                          no audio
                        </span>
                      );
                    }
                    return status.stale ? (
                      <span className="shrink-0 text-xs text-amber-600 dark:text-amber-400">
                        audio stale
                      </span>
                    ) : null;
                  })()}
                </Link>
              ))}
            </div>
          ))}
        </div>
      </ScrollArea>

      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>New dialogue collection</DialogTitle>
          </DialogHeader>
          <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-2">
              <Label className="text-xs text-muted-foreground">
                Quick start
              </Label>
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
    </div>
  );
}
