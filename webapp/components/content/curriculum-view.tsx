"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import {
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { ChevronDown, ChevronRight, ChevronUp, GripVertical } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import {
  dialogueApi,
  scenarioSlug,
  type CollectionSummary,
  type UnitSummary,
} from "@/lib/dialogue/client";
import { cn } from "@/lib/utils";
import { DialogueFormulaNotes } from "@/components/content/dialogue-formula-notes";

function moveItem<T>(items: T[], from: number, to: number): T[] {
  if (to < 0 || to >= items.length || from === to) return items;
  const next = [...items];
  const [item] = next.splice(from, 1);
  next.splice(to, 0, item);
  return next;
}

type EditTarget =
  | { kind: "unit"; id: string }
  | { kind: "collection"; id: string }
  | null;

const UNFILED_KEY = "unfiled";
const unitKey = (id: string) => `unit:${id}`;
const collectionKey = (id: string) => `collection:${id}`;

export function CurriculumView() {
  const queryClient = useQueryClient();
  const [editTarget, setEditTarget] = useState<EditTarget>(null);
  // Everything starts collapsed so the page reads as a table of contents;
  // expand a unit to see its collections, a collection to see its scenarios.
  const [expanded, setExpanded] = useState<Set<string>>(() => new Set());

  const isExpanded = (key: string) => expanded.has(key);

  function setKeysExpanded(keys: string[], open: boolean) {
    setExpanded((current) => {
      const next = new Set(current);
      for (const key of keys) {
        if (open) next.add(key);
        else next.delete(key);
      }
      return next;
    });
  }

  function toggleExpanded(key: string) {
    setKeysExpanded([key], !expanded.has(key));
  }

  const { data: unitsData, isLoading: unitsLoading } = useQuery({
    queryKey: ["curriculum-units"],
    queryFn: dialogueApi.listUnits,
  });

  const { data: collectionsData, isLoading: collectionsLoading } = useQuery({
    queryKey: ["dialogue-collections"],
    queryFn: dialogueApi.listCollections,
  });

  const collectionsById = useMemo(() => {
    const map = new Map<string, CollectionSummary>();
    for (const collection of collectionsData?.collections ?? []) {
      map.set(collection.id, collection);
    }
    return map;
  }, [collectionsData]);

  const units = useMemo(() => {
    const list = [...(unitsData?.units ?? [])];
    list.sort((a, b) => a.orderIndex - b.orderIndex || a.id.localeCompare(b.id));
    return list;
  }, [unitsData]);

  const unfiled = useMemo(() => {
    return (collectionsData?.collections ?? [])
      .filter((c) => !c.unitId)
      .sort((a, b) => a.orderIndex - b.orderIndex || a.id.localeCompare(b.id));
  }, [collectionsData]);

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: ["curriculum-units"] });
    queryClient.invalidateQueries({ queryKey: ["dialogue-collections"] });
  };

  const reorderUnitsMutation = useMutation({
    mutationFn: async (ordered: UnitSummary[]) => {
      await Promise.all(
        ordered.map((unit, index) =>
          dialogueApi.updateUnit(unit.id, { orderIndex: index }),
        ),
      );
    },
    onSuccess: () => {
      invalidate();
      toast.success("Unit order saved.");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const reorderCollectionsMutation = useMutation({
    mutationFn: async ({
      unitId,
      collectionIds,
    }: {
      unitId: string;
      collectionIds: string[];
    }) => {
      await dialogueApi.updateUnit(unitId, { collectionOrder: collectionIds });
    },
    onSuccess: () => {
      invalidate();
      toast.success("Collection order saved.");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const reorderScenariosMutation = useMutation({
    mutationFn: async ({
      collectionId,
      scenarioIds,
    }: {
      collectionId: string;
      scenarioIds: string[];
    }) => {
      await dialogueApi.updateCollection(collectionId, {
        scenarioOrder: scenarioIds,
      });
    },
    onSuccess: () => {
      invalidate();
      toast.success("Scenario order saved.");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const busy =
    reorderUnitsMutation.isPending ||
    reorderCollectionsMutation.isPending ||
    reorderScenariosMutation.isPending;

  const isLoading = unitsLoading || collectionsLoading;

  const allKeys = useMemo(() => {
    const keys: string[] = [];
    for (const unit of units) {
      keys.push(unitKey(unit.id));
      for (const collection of unit.collections ?? []) {
        keys.push(collectionKey(collection.id));
      }
    }
    if (unfiled.length > 0) {
      keys.push(UNFILED_KEY);
      for (const collection of unfiled) keys.push(collectionKey(collection.id));
    }
    return keys;
  }, [units, unfiled]);
  const anyExpanded = allKeys.some((key) => expanded.has(key));

  function toggleUnitEdit(unitId: string) {
    const entering = !(editTarget?.kind === "unit" && editTarget.id === unitId);
    setEditTarget(entering ? { kind: "unit", id: unitId } : null);
    // Reordering collections needs them on screen.
    if (entering) setKeysExpanded([unitKey(unitId)], true);
  }

  function toggleCollectionEdit(collectionId: string) {
    const entering = !(
      editTarget?.kind === "collection" && editTarget.id === collectionId
    );
    setEditTarget(entering ? { kind: "collection", id: collectionId } : null);
    if (entering) setKeysExpanded([collectionKey(collectionId)], true);
  }

  return (
    <div className="flex flex-1 flex-col gap-4 overflow-hidden">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <p className="text-sm text-muted-foreground">
            Scan the learner path. Expand a unit or collection to drill in; Edit
            to reorder that section only.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-7 px-2 text-xs"
            disabled={isLoading || allKeys.length === 0}
            onClick={() => setKeysExpanded(allKeys, !anyExpanded)}
          >
            {anyExpanded ? "Collapse all" : "Expand all"}
          </Button>
          <Badge variant="outline" className="text-xs font-normal">
            View by default
          </Badge>
        </div>
      </div>

      <DialogueFormulaNotes />

      {isLoading ? (
        <div className="flex flex-col gap-3">
          <Skeleton className="h-24 w-full" />
          <Skeleton className="h-24 w-full" />
          <Skeleton className="h-24 w-full" />
        </div>
      ) : units.length === 0 && unfiled.length === 0 ? (
        <div className="flex flex-1 items-center justify-center rounded-lg border border-dashed p-10 text-sm text-muted-foreground">
          No units or collections yet. Create them in Dialogues first.
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto rounded-lg border bg-card/30 p-3">
          <div className="flex flex-col gap-4">
            {units.map((unit, unitIndex) => {
              const unitCollections = (unit.collections ?? [])
                .map((c) => collectionsById.get(c.id))
                .filter((c): c is CollectionSummary => Boolean(c))
                .sort(
                  (a, b) =>
                    a.orderIndex - b.orderIndex || a.id.localeCompare(b.id),
                );

              const scenarioCount = unitCollections.reduce(
                (sum, c) => sum + c.scenarios.length,
                0,
              );
              const publishedCount = unitCollections.reduce(
                (sum, c) =>
                  sum +
                  c.scenarios.filter((s) => Boolean(s.publishedAudioUrl)).length,
                0,
              );

              const editingUnit =
                editTarget?.kind === "unit" && editTarget.id === unit.id;
              const unitOpen = isExpanded(unitKey(unit.id));
              const unitPanelId = `curriculum-unit-${unit.id}`;

              return (
                <section
                  key={unit.id}
                  className={cn(
                    "rounded-lg border bg-background/80 shadow-sm",
                    editingUnit && "ring-1 ring-foreground/15",
                  )}
                >
                  <header
                    className={cn(
                      "flex items-start gap-2 px-3 py-3.5",
                      unitOpen && "border-b",
                    )}
                  >
                    {editingUnit ? (
                      <GripVertical className="mt-1 size-4 shrink-0 text-muted-foreground/50" />
                    ) : null}
                    <button
                      type="button"
                      aria-expanded={unitOpen}
                      aria-controls={unitPanelId}
                      onClick={() => toggleExpanded(unitKey(unit.id))}
                      className="flex min-w-0 flex-1 items-start gap-2 rounded-md text-left touch-manipulation hover:text-foreground"
                    >
                      <ChevronRight
                        className={cn(
                          "mt-0.5 size-4 shrink-0 text-muted-foreground transition-transform",
                          unitOpen && "rotate-90",
                        )}
                      />
                      <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <h2 className="truncate text-sm font-semibold">
                          {unit.title}
                        </h2>
                        <Badge variant="secondary" className="text-[10px]">
                          N{unit.jlptLevel}
                        </Badge>
                        <span className="text-xs text-muted-foreground">
                          {unitCollections.length} collections · {scenarioCount}{" "}
                          scenarios
                        </span>
                        <Badge
                          variant="outline"
                          className={cn(
                            "text-[10px]",
                            publishedCount === scenarioCount && scenarioCount > 0
                              ? "border-emerald-500/40 text-emerald-600 dark:text-emerald-400"
                              : "text-muted-foreground",
                          )}
                        >
                          {publishedCount}/{scenarioCount} published audio
                        </Badge>
                      </div>
                      {unit.subtitle ? (
                        <p className="mt-0.5 truncate text-xs text-muted-foreground">
                          {unit.subtitle}
                        </p>
                      ) : null}
                      </div>
                    </button>
                    <div className="flex shrink-0 items-center gap-1">
                      <Button
                        type="button"
                        variant={editingUnit ? "secondary" : "ghost"}
                        size="sm"
                        className="h-7 px-2 text-xs"
                        onClick={() => toggleUnitEdit(unit.id)}
                      >
                        {editingUnit ? "Done" : "Edit"}
                      </Button>
                      {editingUnit ? (
                        <ReorderButtons
                          disabled={busy}
                          canUp={unitIndex > 0}
                          canDown={unitIndex < units.length - 1}
                          onUp={() =>
                            reorderUnitsMutation.mutate(
                              moveItem(units, unitIndex, unitIndex - 1),
                            )
                          }
                          onDown={() =>
                            reorderUnitsMutation.mutate(
                              moveItem(units, unitIndex, unitIndex + 1),
                            )
                          }
                        />
                      ) : null}
                    </div>
                  </header>

                  {unitOpen ? (
                  <div id={unitPanelId} className="flex flex-col gap-2 p-2 pl-6">
                    {unitCollections.length === 0 ? (
                      <p className="px-2 py-3 text-xs text-muted-foreground">
                        No collections in this unit yet.
                      </p>
                    ) : (
                      unitCollections.map((collection, collectionIndex) => {
                        const scenarios = [...collection.scenarios].sort(
                          (a, b) =>
                            a.orderIndex - b.orderIndex ||
                            a.id.localeCompare(b.id),
                        );
                        const publishedInCollection = scenarios.filter((s) =>
                          Boolean(s.publishedAudioUrl),
                        ).length;
                        const editingCollection =
                          editTarget?.kind === "collection" &&
                          editTarget.id === collection.id;
                        const collectionOpen = isExpanded(
                          collectionKey(collection.id),
                        );
                        const collectionPanelId = `curriculum-collection-${collection.id}`;

                        return (
                          <div
                            key={collection.id}
                            className={cn(
                              "rounded-md border bg-muted/20",
                              editingCollection && "ring-1 ring-foreground/15",
                            )}
                          >
                            <div className="flex items-center gap-1 px-1.5 py-1.5">
                              <button
                                type="button"
                                aria-expanded={collectionOpen}
                                aria-controls={collectionPanelId}
                                aria-label={
                                  collectionOpen
                                    ? `Collapse ${collection.title}`
                                    : `Expand ${collection.title}`
                                }
                                onClick={() =>
                                  toggleExpanded(collectionKey(collection.id))
                                }
                                className="flex size-9 shrink-0 items-center justify-center rounded-md text-muted-foreground touch-manipulation hover:bg-background/60 hover:text-foreground"
                              >
                                <ChevronRight
                                  className={cn(
                                    "size-4 transition-transform",
                                    collectionOpen && "rotate-90",
                                  )}
                                />
                              </button>
                              <div className="min-w-0 flex-1">
                                <Link
                                  href={`/content/dialogues/${collection.id}`}
                                  className="truncate text-sm font-medium hover:underline"
                                >
                                  {collection.title}
                                </Link>
                                <p className="text-[11px] text-muted-foreground">
                                  {scenarios.length} scenarios ·{" "}
                                  {publishedInCollection}/{scenarios.length} audio
                                </p>
                              </div>
                              <div className="flex shrink-0 items-center gap-1">
                                <Button
                                  type="button"
                                  variant={
                                    editingCollection ? "secondary" : "ghost"
                                  }
                                  size="sm"
                                  className="h-7 px-2 text-xs"
                                  onClick={() =>
                                    toggleCollectionEdit(collection.id)
                                  }
                                >
                                  {editingCollection ? "Done" : "Edit"}
                                </Button>
                                {editingUnit ? (
                                  <ReorderButtons
                                    disabled={busy}
                                    canUp={collectionIndex > 0}
                                    canDown={
                                      collectionIndex <
                                      unitCollections.length - 1
                                    }
                                    onUp={() =>
                                      reorderCollectionsMutation.mutate({
                                        unitId: unit.id,
                                        collectionIds: moveItem(
                                          unitCollections,
                                          collectionIndex,
                                          collectionIndex - 1,
                                        ).map((c) => c.id),
                                      })
                                    }
                                    onDown={() =>
                                      reorderCollectionsMutation.mutate({
                                        unitId: unit.id,
                                        collectionIds: moveItem(
                                          unitCollections,
                                          collectionIndex,
                                          collectionIndex + 1,
                                        ).map((c) => c.id),
                                      })
                                    }
                                  />
                                ) : null}
                              </div>
                            </div>
                            {collectionOpen ? (
                            <ol id={collectionPanelId} className="border-t px-2 py-1.5">
                              {scenarios.map((scenario, scenarioIndex) => (
                                <li
                                  key={scenario.id}
                                  className="flex items-center gap-2 rounded px-1 py-1.5 hover:bg-background/60"
                                >
                                  <span className="w-5 shrink-0 text-right text-[10px] text-muted-foreground">
                                    {scenarioIndex + 1}
                                  </span>
                                  <Link
                                    href={`/content/dialogues/${collection.id}/${scenarioSlug(scenario)}`}
                                    className="min-w-0 flex-1 truncate text-xs hover:underline"
                                  >
                                    {scenario.menuTitle}
                                  </Link>
                                  {scenario.publishedAudioUrl ? (
                                    <Badge
                                      variant="outline"
                                      className="text-[9px] border-emerald-500/40 text-emerald-600 dark:text-emerald-400"
                                    >
                                      audio
                                    </Badge>
                                  ) : (
                                    <Badge
                                      variant="outline"
                                      className="text-[9px] text-muted-foreground"
                                    >
                                      draft
                                    </Badge>
                                  )}
                                  {editingCollection ? (
                                    <ReorderButtons
                                      size="xs"
                                      disabled={busy}
                                      canUp={scenarioIndex > 0}
                                      canDown={
                                        scenarioIndex < scenarios.length - 1
                                      }
                                      onUp={() =>
                                        reorderScenariosMutation.mutate({
                                          collectionId: collection.id,
                                          scenarioIds: moveItem(
                                            scenarios,
                                            scenarioIndex,
                                            scenarioIndex - 1,
                                          ).map((s) => s.id),
                                        })
                                      }
                                      onDown={() =>
                                        reorderScenariosMutation.mutate({
                                          collectionId: collection.id,
                                          scenarioIds: moveItem(
                                            scenarios,
                                            scenarioIndex,
                                            scenarioIndex + 1,
                                          ).map((s) => s.id),
                                        })
                                      }
                                    />
                                  ) : null}
                                </li>
                              ))}
                            </ol>
                            ) : null}
                          </div>
                        );
                      })
                    )}
                  </div>
                  ) : null}
                </section>
              );
            })}

            {unfiled.length > 0 ? (
              <section className="rounded-lg border border-dashed bg-background/40">
                <header
                  className={cn(
                    "px-3 py-2.5",
                    isExpanded(UNFILED_KEY) && "border-b border-dashed",
                  )}
                >
                  <button
                    type="button"
                    aria-expanded={isExpanded(UNFILED_KEY)}
                    aria-controls="curriculum-unfiled"
                    onClick={() => toggleExpanded(UNFILED_KEY)}
                    className="flex w-full items-start gap-2 text-left touch-manipulation"
                  >
                    <ChevronRight
                      className={cn(
                        "mt-0.5 size-4 shrink-0 text-muted-foreground transition-transform",
                        isExpanded(UNFILED_KEY) && "rotate-90",
                      )}
                    />
                    <div className="min-w-0 flex-1">
                      <h2 className="text-sm font-semibold text-muted-foreground">
                        Unfiled
                        <span className="ml-2 text-xs font-normal">
                          {unfiled.length} collection{unfiled.length === 1 ? "" : "s"}
                        </span>
                      </h2>
                      <p className="text-xs text-muted-foreground">
                        Collections not assigned to a unit. Assign them in Dialogues.
                        Edit a collection below to reorder its scenarios.
                      </p>
                    </div>
                  </button>
                </header>
                {isExpanded(UNFILED_KEY) ? (
                <ul id="curriculum-unfiled" className="flex flex-col gap-2 p-2">
                  {unfiled.map((collection) => {
                    const scenarios = [...collection.scenarios].sort(
                      (a, b) =>
                        a.orderIndex - b.orderIndex || a.id.localeCompare(b.id),
                    );
                    const editingCollection =
                      editTarget?.kind === "collection" &&
                      editTarget.id === collection.id;
                    const collectionOpen = isExpanded(collectionKey(collection.id));
                    const collectionPanelId = `curriculum-collection-${collection.id}`;
                    return (
                      <li
                        key={collection.id}
                        className={cn(
                          "rounded-md border bg-muted/10",
                          editingCollection && "ring-1 ring-foreground/15",
                        )}
                      >
                        <div className="flex items-center gap-1 px-1.5 py-1.5">
                          <button
                            type="button"
                            aria-expanded={collectionOpen}
                            aria-controls={collectionPanelId}
                            aria-label={
                              collectionOpen
                                ? `Collapse ${collection.title}`
                                : `Expand ${collection.title}`
                            }
                            onClick={() =>
                              toggleExpanded(collectionKey(collection.id))
                            }
                            className="flex size-9 shrink-0 items-center justify-center rounded-md text-muted-foreground touch-manipulation hover:bg-background/60 hover:text-foreground"
                          >
                            <ChevronRight
                              className={cn(
                                "size-4 transition-transform",
                                collectionOpen && "rotate-90",
                              )}
                            />
                          </button>
                          <Link
                            href={`/content/dialogues/${collection.id}`}
                            className="min-w-0 flex-1 truncate text-sm hover:underline"
                          >
                            {collection.title}
                            <span className="ml-2 text-xs text-muted-foreground">
                              {scenarios.length} scenarios
                            </span>
                          </Link>
                          <Button
                            type="button"
                            variant={editingCollection ? "secondary" : "ghost"}
                            size="sm"
                            className="h-7 px-2 text-xs"
                            onClick={() =>
                              toggleCollectionEdit(collection.id)
                            }
                          >
                            {editingCollection ? "Done" : "Edit"}
                          </Button>
                        </div>
                        {collectionOpen ? (
                          <ol id={collectionPanelId} className="border-t px-2 py-1.5">
                            {scenarios.map((scenario, scenarioIndex) => (
                              <li
                                key={scenario.id}
                                className="flex items-center gap-2 rounded px-1 py-1.5"
                              >
                                <span className="w-5 shrink-0 text-right text-[10px] text-muted-foreground">
                                  {scenarioIndex + 1}
                                </span>
                                <Link
                                  href={`/content/dialogues/${collection.id}/${scenarioSlug(scenario)}`}
                                  className="min-w-0 flex-1 truncate text-xs hover:underline"
                                >
                                  {scenario.menuTitle}
                                </Link>
                                {scenario.publishedAudioUrl ? (
                                  <Badge
                                    variant="outline"
                                    className="text-[9px] border-emerald-500/40 text-emerald-600 dark:text-emerald-400"
                                  >
                                    audio
                                  </Badge>
                                ) : (
                                  <Badge
                                    variant="outline"
                                    className="text-[9px] text-muted-foreground"
                                  >
                                    draft
                                  </Badge>
                                )}
                                {editingCollection ? (
                                <ReorderButtons
                                  size="xs"
                                  disabled={busy}
                                  canUp={scenarioIndex > 0}
                                  canDown={
                                    scenarioIndex < scenarios.length - 1
                                  }
                                  onUp={() =>
                                    reorderScenariosMutation.mutate({
                                      collectionId: collection.id,
                                      scenarioIds: moveItem(
                                        scenarios,
                                        scenarioIndex,
                                        scenarioIndex - 1,
                                      ).map((s) => s.id),
                                    })
                                  }
                                  onDown={() =>
                                    reorderScenariosMutation.mutate({
                                      collectionId: collection.id,
                                      scenarioIds: moveItem(
                                        scenarios,
                                        scenarioIndex,
                                        scenarioIndex + 1,
                                      ).map((s) => s.id),
                                    })
                                  }
                                />
                                ) : null}
                              </li>
                            ))}
                          </ol>
                        ) : null}
                      </li>
                    );
                  })}
                </ul>
                ) : null}
              </section>
            ) : null}
          </div>
        </div>
      )}
    </div>
  );
}

function ReorderButtons({
  canUp,
  canDown,
  onUp,
  onDown,
  disabled,
  size = "sm",
}: {
  canUp: boolean;
  canDown: boolean;
  onUp: () => void;
  onDown: () => void;
  disabled?: boolean;
  size?: "sm" | "xs";
}) {
  const buttonClass = size === "xs" ? "size-6" : "size-7";
  const iconClass = size === "xs" ? "size-3" : "size-3.5";
  return (
    <div className="flex shrink-0 flex-col gap-0.5">
      <Button
        type="button"
        variant="ghost"
        size="icon"
        className={buttonClass}
        disabled={disabled || !canUp}
        onClick={onUp}
        aria-label="Move up"
      >
        <ChevronUp className={iconClass} />
      </Button>
      <Button
        type="button"
        variant="ghost"
        size="icon"
        className={buttonClass}
        disabled={disabled || !canDown}
        onClick={onDown}
        aria-label="Move down"
      >
        <ChevronDown className={iconClass} />
      </Button>
    </div>
  );
}
