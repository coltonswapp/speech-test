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
import { FileJson, FolderPlus, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import {
  dialogueApi,
  scenarioSlug,
  type UnitSummary,
} from "@/lib/dialogue/client";
import { CreateCollectionDialog } from "@/components/dialogue/create-collection-dialog";

export function DialogueList({
  activeId,
  className,
}: {
  activeId?: string;
  className?: string;
}) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const importInputRef = useRef<HTMLInputElement>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [createUnitOpen, setCreateUnitOpen] = useState(false);
  const [newUnitSlug, setNewUnitSlug] = useState("");
  const [newUnitTitle, setNewUnitTitle] = useState("");
  const [newUnitJlpt, setNewUnitJlpt] = useState("5");

  const { data, isLoading } = useQuery({
    queryKey: ["dialogue-collections"],
    queryFn: dialogueApi.listCollections,
  });

  const { data: unitsData } = useQuery({
    queryKey: ["curriculum-units"],
    queryFn: dialogueApi.listUnits,
  });

  const createUnitMutation = useMutation({
    mutationFn: () =>
      dialogueApi.createUnit({
        id: newUnitSlug.trim(),
        title: newUnitTitle.trim(),
        jlptLevel: Number(newUnitJlpt),
        orderIndex: unitsData?.units.length ?? 0,
      }),
    onSuccess: ({ unit }) => {
      queryClient.invalidateQueries({ queryKey: ["curriculum-units"] });
      setCreateUnitOpen(false);
      setNewUnitSlug("");
      setNewUnitTitle("");
      setNewUnitJlpt("5");
      toast.success(`Unit "${unit.title}" created.`);
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
  const units = unitsData?.units ?? [];

  // One group per curriculum unit (in unit order), plus an unfiled group for
  // collections without a unit (or whose unit no longer exists).
  const groups = [
    ...units.map((unit) => ({
      key: unit.id,
      label: unit.title,
      jlptLevel: unit.jlptLevel as number | null,
      unit,
      collections: collections.filter((c) => c.unitId === unit.id),
    })),
    {
      key: "__unfiled__",
      label: units.length > 0 ? "Unfiled" : null,
      jlptLevel: null,
      unit: null as UnitSummary | null,
      collections: collections.filter(
        (c) => !units.some((unit) => unit.id === c.unitId),
      ),
    },
  ];

  const audioStatusQueries = useQueries({
    queries: collections.map((collection) => ({
      queryKey: ["dialogue-collection-audio-status", collection.id],
      queryFn: () => dialogueApi.audioStatus(collection.id),
    })),
  });
  const audioStatusById = new Map(
    audioStatusQueries.flatMap(
      (query) => query.data?.scenarios.map((s) => [s.id, s] as const) ?? [],
    ),
  );

  return (
    <div
      className={cn(
        "flex w-80 shrink-0 flex-col gap-3 border-r border-border/60 pr-4",
        className,
      )}
    >

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
      <Button
        size="sm"
        variant="outline"
        className="w-full justify-start gap-2"
        onClick={() => setCreateUnitOpen(true)}
      >
        <FolderPlus className="size-4" />
        New unit
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

          {groups.map((group) => (
            <div key={group.key} className="flex flex-col gap-2">
              {group.label && (
                <div className="flex items-center justify-between gap-2 px-2 pt-1">
                  {group.unit ? (
                    <Link
                      href={`/content/dialogues/units/${group.unit.id}`}
                      className={cn(
                        "truncate text-xs font-semibold uppercase tracking-wide transition-colors",
                        group.unit.id === activeId
                          ? "text-foreground"
                          : "text-muted-foreground hover:text-foreground",
                      )}
                    >
                      {group.label}
                    </Link>
                  ) : (
                    <span className="truncate text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                      {group.label}
                    </span>
                  )}
                  {group.jlptLevel != null && (
                    <span className="shrink-0 rounded bg-muted px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground">
                      N{group.jlptLevel}
                    </span>
                  )}
                </div>
              )}
              {group.label && group.collections.length === 0 && (
                <p className="px-2 text-xs text-muted-foreground">
                  No collections yet
                </p>
              )}
              {group.collections.map((collection) => (
                <div key={collection.id} className="flex flex-col gap-1">
                  <Link
                    href={`/content/dialogues/${collection.id}`}
                    className={cn(
                      "flex flex-col rounded-md px-3 py-2 text-sm transition-colors",
                      collection.id === activeId
                        ? "bg-accent text-accent-foreground"
                        : "hover:bg-accent/50",
                    )}
                  >
                    <span className="truncate font-medium">
                      {collection.title}
                    </span>
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
                          : "hover:bg-accent/50",
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
          ))}
        </div>
      </ScrollArea>

      <CreateCollectionDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        units={units}
      />

      <Dialog open={createUnitOpen} onOpenChange={setCreateUnitOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>New curriculum unit</DialogTitle>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <p className="text-sm text-muted-foreground">
              Units are the grammar bands that group collections into a
              sequenced curriculum. Collections without a unit stay under
              Unfiled.
            </p>
            <div className="flex flex-col gap-2">
              <Label>ID (slug, immutable)</Label>
              <Input
                value={newUnitSlug}
                onChange={(e) => setNewUnitSlug(e.target.value)}
                placeholder="n5-foundations"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label>Title</Label>
              <Input
                value={newUnitTitle}
                onChange={(e) => setNewUnitTitle(e.target.value)}
                placeholder="N5 Foundations"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label>JLPT level</Label>
              <Select
                value={newUnitJlpt}
                onValueChange={(value) => setNewUnitJlpt(value ?? "5")}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {[5, 4, 3, 2, 1].map((level) => (
                    <SelectItem key={level} value={String(level)}>
                      N{level}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <Button
              onClick={() => createUnitMutation.mutate()}
              disabled={
                createUnitMutation.isPending ||
                !newUnitSlug.trim() ||
                !newUnitTitle.trim()
              }
            >
              Create
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
