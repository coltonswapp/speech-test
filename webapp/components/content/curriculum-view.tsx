"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import {
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { ChevronDown, ChevronUp, GripVertical } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { SectionSwitcher } from "@/components/content/section-switcher";
import {
  dialogueApi,
  scenarioSlug,
  type CollectionSummary,
  type UnitSummary,
} from "@/lib/dialogue/client";
import { cn } from "@/lib/utils";

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

export function CurriculumView() {
  const queryClient = useQueryClient();
  const [editTarget, setEditTarget] = useState<EditTarget>(null);

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

  function toggleUnitEdit(unitId: string) {
    setEditTarget((current) =>
      current?.kind === "unit" && current.id === unitId
        ? null
        : { kind: "unit", id: unitId },
    );
  }

  function toggleCollectionEdit(collectionId: string) {
    setEditTarget((current) =>
      current?.kind === "collection" && current.id === collectionId
        ? null
        : { kind: "collection", id: collectionId },
    );
  }

  return (
    <div className="flex flex-1 flex-col gap-4 overflow-hidden">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <SectionSwitcher active="curriculum" />
          <p className="text-sm text-muted-foreground">
            Scan the learner path. Edit a unit or collection to reorder that
            section only.
          </p>
        </div>
        <Badge variant="outline" className="text-xs font-normal">
          View by default
        </Badge>
      </div>

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

              return (
                <section
                  key={unit.id}
                  className={cn(
                    "rounded-lg border bg-background/80 shadow-sm",
                    editingUnit && "ring-1 ring-foreground/15",
                  )}
                >
                  <header className="flex items-start gap-2 border-b px-3 py-3.5">
                    {editingUnit ? (
                      <GripVertical className="mt-1 size-4 shrink-0 text-muted-foreground/50" />
                    ) : null}
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

                  <div className="flex flex-col gap-2 p-2 pl-6">
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
                        const editingCollection =
                          editTarget?.kind === "collection" &&
                          editTarget.id === collection.id;

                        return (
                          <div
                            key={collection.id}
                            className={cn(
                              "rounded-md border bg-muted/20",
                              editingCollection && "ring-1 ring-foreground/15",
                            )}
                          >
                            <div className="flex items-center gap-2 px-2.5 py-2.5">
                              <div className="min-w-0 flex-1">
                                <Link
                                  href={`/content/dialogues/${collection.id}`}
                                  className="truncate text-sm font-medium hover:underline"
                                >
                                  {collection.title}
                                </Link>
                                <p className="text-[11px] text-muted-foreground">
                                  {scenarios.length} scenarios
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
                            <ol className="border-t px-2 py-1.5">
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
                          </div>
                        );
                      })
                    )}
                  </div>
                </section>
              );
            })}

            {unfiled.length > 0 ? (
              <section className="rounded-lg border border-dashed bg-background/40">
                <header className="border-b border-dashed px-3 py-2.5">
                  <h2 className="text-sm font-semibold text-muted-foreground">
                    Unfiled
                  </h2>
                  <p className="text-xs text-muted-foreground">
                    Collections not assigned to a unit. Assign them in Dialogues.
                    Edit a collection below to reorder its scenarios.
                  </p>
                </header>
                <ul className="flex flex-col gap-2 p-2">
                  {unfiled.map((collection) => {
                    const scenarios = [...collection.scenarios].sort(
                      (a, b) =>
                        a.orderIndex - b.orderIndex || a.id.localeCompare(b.id),
                    );
                    const editingCollection =
                      editTarget?.kind === "collection" &&
                      editTarget.id === collection.id;
                    return (
                      <li
                        key={collection.id}
                        className={cn(
                          "rounded-md border bg-muted/10",
                          editingCollection && "ring-1 ring-foreground/15",
                        )}
                      >
                        <div className="flex items-center gap-2 px-2.5 py-2">
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
                        {editingCollection ? (
                          <ol className="border-t px-2 py-1.5">
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
                              </li>
                            ))}
                          </ol>
                        ) : null}
                      </li>
                    );
                  })}
                </ul>
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
