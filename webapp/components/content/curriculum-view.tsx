"use client";

import { useMemo, useState, type CSSProperties } from "react";
import Link from "next/link";
import {
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import type {
  DraggableAttributes,
  DraggableSyntheticListeners,
} from "@dnd-kit/core";
import { ChevronRight } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import {
  dialogueApi,
  scenarioSlug,
  type CollectionSummary,
  type ScenarioSummary,
  type UnitSummary,
} from "@/lib/dialogue/client";
import {
  ScenarioReadinessChips,
  ScenarioUpdatedLabel,
} from "@/components/dialogue/scenario-readiness-chips";
import { DialogueFormulaNotes } from "@/components/content/dialogue-formula-notes";
import {
  CurriculumDragHandle,
  SortableItem,
  SortableList,
} from "@/components/content/curriculum-sortable";
import { cn } from "@/lib/utils";

type EditTarget =
  | { kind: "unit"; id: string }
  | { kind: "collection"; id: string }
  | null;

const UNFILED_KEY = "unfiled";
const unitKey = (id: string) => `unit:${id}`;
const collectionKey = (id: string) => `collection:${id}`;

type UnitsQueryData = { units: UnitSummary[] };
type CollectionsQueryData = { collections: CollectionSummary[] };

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

  function sectionKeys(sectionKey: string, collectionIds: string[]) {
    return [sectionKey, ...collectionIds.map(collectionKey)];
  }

  function isSectionExpanded(sectionKey: string, collectionIds: string[]) {
    return sectionKeys(sectionKey, collectionIds).every((key) =>
      expanded.has(key),
    );
  }

  function toggleSection(sectionKey: string, collectionIds: string[]) {
    const keys = sectionKeys(sectionKey, collectionIds);
    const open = !isSectionExpanded(sectionKey, collectionIds);
    setKeysExpanded(keys, open);
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
    mutationFn: async (orderedIds: string[]) => {
      await Promise.all(
        orderedIds.map((id, index) =>
          dialogueApi.updateUnit(id, { orderIndex: index }),
        ),
      );
    },
    onMutate: async (orderedIds) => {
      await queryClient.cancelQueries({ queryKey: ["curriculum-units"] });
      const previous = queryClient.getQueryData<UnitsQueryData>([
        "curriculum-units",
      ]);
      if (previous) {
        const byId = new Map(previous.units.map((unit) => [unit.id, unit]));
        queryClient.setQueryData<UnitsQueryData>(["curriculum-units"], {
          units: orderedIds.flatMap((id, index) => {
            const unit = byId.get(id);
            return unit ? [{ ...unit, orderIndex: index }] : [];
          }),
        });
      }
      return { previous };
    },
    onError: (error: Error, _vars, context) => {
      if (context?.previous) {
        queryClient.setQueryData(["curriculum-units"], context.previous);
      }
      toast.error(error.message);
    },
    onSuccess: () => {
      invalidate();
      toast.success("Unit order saved.");
    },
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
    onMutate: async ({ unitId, collectionIds }) => {
      await queryClient.cancelQueries({ queryKey: ["curriculum-units"] });
      await queryClient.cancelQueries({ queryKey: ["dialogue-collections"] });
      const previousUnits = queryClient.getQueryData<UnitsQueryData>([
        "curriculum-units",
      ]);
      const previousCollections =
        queryClient.getQueryData<CollectionsQueryData>(["dialogue-collections"]);

      if (previousUnits) {
        queryClient.setQueryData<UnitsQueryData>(["curriculum-units"], {
          units: previousUnits.units.map((unit) => {
            if (unit.id !== unitId) return unit;
            const byId = new Map(
              unit.collections.map((collection) => [collection.id, collection]),
            );
            return {
              ...unit,
              collections: collectionIds.flatMap((id) => {
                const collection = byId.get(id);
                return collection ? [collection] : [];
              }),
            };
          }),
        });
      }

      if (previousCollections) {
        queryClient.setQueryData<CollectionsQueryData>(
          ["dialogue-collections"],
          {
            collections: previousCollections.collections.map((collection) => {
              const index = collectionIds.indexOf(collection.id);
              if (index < 0) return collection;
              return { ...collection, orderIndex: index };
            }),
          },
        );
      }

      return { previousUnits, previousCollections };
    },
    onError: (error: Error, _vars, context) => {
      if (context?.previousUnits) {
        queryClient.setQueryData(["curriculum-units"], context.previousUnits);
      }
      if (context?.previousCollections) {
        queryClient.setQueryData(
          ["dialogue-collections"],
          context.previousCollections,
        );
      }
      toast.error(error.message);
    },
    onSuccess: () => {
      invalidate();
      toast.success("Collection order saved.");
    },
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
    onMutate: async ({ collectionId, scenarioIds }) => {
      await queryClient.cancelQueries({ queryKey: ["dialogue-collections"] });
      const previous = queryClient.getQueryData<CollectionsQueryData>([
        "dialogue-collections",
      ]);
      if (previous) {
        queryClient.setQueryData<CollectionsQueryData>(
          ["dialogue-collections"],
          {
            collections: previous.collections.map((collection) => {
              if (collection.id !== collectionId) return collection;
              const byId = new Map(
                collection.scenarios.map((scenario) => [scenario.id, scenario]),
              );
              return {
                ...collection,
                scenarios: scenarioIds.flatMap((id, index) => {
                  const scenario = byId.get(id);
                  return scenario
                    ? [{ ...scenario, orderIndex: index }]
                    : [];
                }),
              };
            }),
          },
        );
      }
      return { previous };
    },
    onError: (error: Error, _vars, context) => {
      if (context?.previous) {
        queryClient.setQueryData(["dialogue-collections"], context.previous);
      }
      toast.error(error.message);
    },
    onSuccess: () => {
      invalidate();
      toast.success("Scenario order saved.");
    },
  });

  const activateMutation = useMutation({
    mutationFn: ({
      collectionId,
      isActive,
    }: {
      collectionId: string;
      isActive: boolean;
    }) => dialogueApi.updateCollection(collectionId, { isActive }),
    onSuccess: (_, { isActive }) => {
      invalidate();
      queryClient.invalidateQueries({ queryKey: ["dialogue-collection"] });
      toast.success(
        isActive ? "Lesson is live in the app." : "Lesson hidden from the app.",
      );
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const busy =
    reorderUnitsMutation.isPending ||
    reorderCollectionsMutation.isPending ||
    reorderScenariosMutation.isPending;

  function collectionActivationPending(collectionId: string) {
    return (
      activateMutation.isPending &&
      activateMutation.variables?.collectionId === collectionId
    );
  }

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
  const unfiledCollectionIds = useMemo(
    () => unfiled.map((c) => c.id),
    [unfiled],
  );
  const unfiledSectionOpen = isSectionExpanded(
    UNFILED_KEY,
    unfiledCollectionIds,
  );
  const unitIds = useMemo(() => units.map((unit) => unit.id), [units]);

  function toggleUnitEdit(unitId: string) {
    const entering = !(editTarget?.kind === "unit" && editTarget.id === unitId);
    setEditTarget(entering ? { kind: "unit", id: unitId } : null);
    // Highlighting a unit needs its collections on screen.
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
            Scan the learner path. Open a unit or collection title to edit it.
            Expand a section, then drag the grip to reorder. Reorder expands
            and highlights that section.
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
            Drag when expanded
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
            {units.length > 0 ? (
              <SortableList
                items={unitIds}
                disabled={busy}
                onReorder={(orderedIds) =>
                  reorderUnitsMutation.mutate(orderedIds)
                }
                className="flex flex-col gap-4"
              >
                {units.map((unit) => {
                  const unitCollections = (unit.collections ?? [])
                    .map((c) => collectionsById.get(c.id))
                    .filter((c): c is CollectionSummary => Boolean(c))
                    .sort(
                      (a, b) =>
                        a.orderIndex - b.orderIndex ||
                        a.id.localeCompare(b.id),
                    );

                  const scenarioCount = unitCollections.reduce(
                    (sum, c) => sum + c.scenarios.length,
                    0,
                  );
                  const publishedCount = unitCollections.reduce(
                    (sum, c) =>
                      sum +
                      c.scenarios.filter((s) =>
                        Boolean(s.publishedAudioUrl),
                      ).length,
                    0,
                  );

                  const editingUnit =
                    editTarget?.kind === "unit" && editTarget.id === unit.id;
                  const unitOpen = isExpanded(unitKey(unit.id));
                  const unitPanelId = `curriculum-unit-${unit.id}`;
                  const unitCollectionIds = unitCollections.map((c) => c.id);
                  const unitSectionOpen = isSectionExpanded(
                    unitKey(unit.id),
                    unitCollectionIds,
                  );

                  return (
                    <SortableItem key={unit.id} id={unit.id} disabled={busy}>
                      {({
                        setNodeRef,
                        style,
                        attributes,
                        listeners,
                        isDragging,
                      }) => (
                        <section
                          ref={setNodeRef}
                          style={style}
                          className={cn(
                            "rounded-lg border bg-background/80 shadow-sm",
                            editingUnit && "ring-1 ring-foreground/15",
                            isDragging && "shadow-md ring-1 ring-foreground/20",
                          )}
                        >
                          <header
                            className={cn(
                              "flex items-start gap-1 px-2 py-3.5 sm:gap-2 sm:px-3",
                              unitOpen && "border-b",
                            )}
                          >
                            <CurriculumDragHandle
                              attributes={attributes}
                              listeners={listeners}
                              disabled={busy}
                              className="mt-0.5"
                              label={`Reorder unit ${unit.title}`}
                            />
                            <button
                              type="button"
                              aria-expanded={unitOpen}
                              aria-controls={unitPanelId}
                              aria-label={
                                unitOpen
                                  ? `Collapse ${unit.title}`
                                  : `Expand ${unit.title}`
                              }
                              onClick={() => toggleExpanded(unitKey(unit.id))}
                              className="flex size-9 shrink-0 items-center justify-center rounded-md text-muted-foreground touch-manipulation hover:bg-background/60 hover:text-foreground"
                            >
                              <ChevronRight
                                className={cn(
                                  "size-4 transition-transform",
                                  unitOpen && "rotate-90",
                                )}
                              />
                            </button>
                            <div className="min-w-0 flex-1">
                              <div className="flex flex-wrap items-center gap-2">
                                <Link
                                  href={`/content/dialogues/units/${unit.id}`}
                                  className="truncate text-sm font-semibold hover:underline"
                                >
                                  {unit.title}
                                </Link>
                                <Badge
                                  variant="secondary"
                                  className="text-[10px]"
                                >
                                  N{unit.jlptLevel}
                                </Badge>
                                <span className="text-xs text-muted-foreground">
                                  {unitCollections.length} collections ·{" "}
                                  {scenarioCount} scenarios
                                </span>
                                <Badge
                                  variant="outline"
                                  className={cn(
                                    "text-[10px]",
                                    publishedCount === scenarioCount &&
                                      scenarioCount > 0
                                      ? "border-emerald-500/40 text-emerald-600 dark:text-emerald-400"
                                      : "text-muted-foreground",
                                  )}
                                >
                                  {publishedCount}/{scenarioCount} published
                                  audio
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
                                variant="ghost"
                                size="sm"
                                className="h-7 px-2 text-xs"
                                onClick={() =>
                                  toggleSection(
                                    unitKey(unit.id),
                                    unitCollectionIds,
                                  )
                                }
                                title={
                                  unitSectionOpen
                                    ? "Collapse this unit and its collections"
                                    : "Expand this unit and all collections"
                                }
                              >
                                {unitSectionOpen
                                  ? "Collapse section"
                                  : "Expand section"}
                              </Button>
                              <Button
                                type="button"
                                variant={editingUnit ? "secondary" : "ghost"}
                                size="sm"
                                className="h-7 px-2 text-xs"
                                onClick={() => toggleUnitEdit(unit.id)}
                                title="Expand and highlight this unit for drag reorder"
                              >
                                {editingUnit ? "Done" : "Reorder"}
                              </Button>
                            </div>
                          </header>

                          {unitOpen ? (
                            <div
                              id={unitPanelId}
                              className="flex flex-col gap-2 p-2 pl-4 sm:pl-6"
                            >
                              {unitCollections.length === 0 ? (
                                <p className="px-2 py-3 text-xs text-muted-foreground">
                                  No collections in this unit yet.
                                </p>
                              ) : (
                                <SortableList
                                  items={unitCollectionIds}
                                  disabled={busy}
                                  onReorder={(collectionIds) =>
                                    reorderCollectionsMutation.mutate({
                                      unitId: unit.id,
                                      collectionIds,
                                    })
                                  }
                                  className="flex flex-col gap-2"
                                >
                                  {unitCollections.map((collection) => (
                                    <CurriculumCollectionBlock
                                      key={collection.id}
                                      collection={collection}
                                      busy={busy}
                                      editing={
                                        editTarget?.kind === "collection" &&
                                        editTarget.id === collection.id
                                      }
                                      open={isExpanded(
                                        collectionKey(collection.id),
                                      )}
                                      onToggleOpen={() =>
                                        toggleExpanded(
                                          collectionKey(collection.id),
                                        )
                                      }
                                      onToggleEdit={() =>
                                        toggleCollectionEdit(collection.id)
                                      }
                                      activationPending={collectionActivationPending(
                                        collection.id,
                                      )}
                                      onToggleActive={(isActive) =>
                                        activateMutation.mutate({
                                          collectionId: collection.id,
                                          isActive,
                                        })
                                      }
                                      onReorderScenarios={(scenarioIds) =>
                                        reorderScenariosMutation.mutate({
                                          collectionId: collection.id,
                                          scenarioIds,
                                        })
                                      }
                                    />
                                  ))}
                                </SortableList>
                              )}
                            </div>
                          ) : null}
                        </section>
                      )}
                    </SortableItem>
                  );
                })}
              </SortableList>
            ) : null}

            {unfiled.length > 0 ? (
              <section className="rounded-lg border border-dashed bg-background/40">
                <header
                  className={cn(
                    "flex items-start gap-2 px-3 py-2.5",
                    isExpanded(UNFILED_KEY) && "border-b border-dashed",
                  )}
                >
                  <button
                    type="button"
                    aria-expanded={isExpanded(UNFILED_KEY)}
                    aria-controls="curriculum-unfiled"
                    onClick={() => toggleExpanded(UNFILED_KEY)}
                    className="flex min-w-0 flex-1 items-start gap-2 text-left touch-manipulation"
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
                          {unfiled.length} collection
                          {unfiled.length === 1 ? "" : "s"}
                        </span>
                      </h2>
                      <p className="text-xs text-muted-foreground">
                        Collections not assigned to a unit. Assign them in
                        Dialogues. Expand a collection and drag scenarios to
                        reorder.
                      </p>
                    </div>
                  </button>
                  <div className="flex shrink-0 items-center gap-1">
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      className="h-7 px-2 text-xs"
                      onClick={() =>
                        toggleSection(UNFILED_KEY, unfiledCollectionIds)
                      }
                      title={
                        unfiledSectionOpen
                          ? "Collapse Unfiled and its collections"
                          : "Expand Unfiled and all collections"
                      }
                    >
                      {unfiledSectionOpen
                        ? "Collapse section"
                        : "Expand section"}
                    </Button>
                  </div>
                </header>
                {isExpanded(UNFILED_KEY) ? (
                  <ul
                    id="curriculum-unfiled"
                    className="flex flex-col gap-2 p-2"
                  >
                    {unfiled.map((collection) => (
                      <li key={collection.id}>
                        <CurriculumCollectionBlock
                          collection={collection}
                          busy={busy}
                          sortable={false}
                          editing={
                            editTarget?.kind === "collection" &&
                            editTarget.id === collection.id
                          }
                          open={isExpanded(collectionKey(collection.id))}
                          onToggleOpen={() =>
                            toggleExpanded(collectionKey(collection.id))
                          }
                          onToggleEdit={() =>
                            toggleCollectionEdit(collection.id)
                          }
                          activationPending={collectionActivationPending(
                            collection.id,
                          )}
                          onToggleActive={(isActive) =>
                            activateMutation.mutate({
                              collectionId: collection.id,
                              isActive,
                            })
                          }
                          onReorderScenarios={(scenarioIds) =>
                            reorderScenariosMutation.mutate({
                              collectionId: collection.id,
                              scenarioIds,
                            })
                          }
                        />
                      </li>
                    ))}
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

function CurriculumCollectionBlock({
  collection,
  busy,
  editing,
  open,
  onToggleOpen,
  onToggleEdit,
  activationPending,
  onToggleActive,
  onReorderScenarios,
  sortable = true,
}: {
  collection: CollectionSummary;
  busy: boolean;
  editing: boolean;
  open: boolean;
  onToggleOpen: () => void;
  onToggleEdit: () => void;
  activationPending: boolean;
  onToggleActive: (isActive: boolean) => void;
  onReorderScenarios: (scenarioIds: string[]) => void;
  /** Unfiled collections have no unit-level order API; skip collection drag. */
  sortable?: boolean;
}) {
  const scenarios = useMemo(
    () =>
      [...collection.scenarios].sort(
        (a, b) => a.orderIndex - b.orderIndex || a.id.localeCompare(b.id),
      ),
    [collection.scenarios],
  );
  const scenarioIds = useMemo(
    () => scenarios.map((scenario) => scenario.id),
    [scenarios],
  );
  const publishedInCollection = scenarios.filter((s) =>
    Boolean(s.publishedAudioUrl),
  ).length;
  const collectionPanelId = `curriculum-collection-${collection.id}`;

  const body = (
    setNodeRef?: (node: HTMLElement | null) => void,
    style?: CSSProperties,
    dragHandle?: {
      attributes: DraggableAttributes;
      listeners: DraggableSyntheticListeners;
    },
    isDragging?: boolean,
  ) => (
    <div
      ref={setNodeRef}
      style={style}
      className={cn(
        "rounded-md border bg-muted/20",
        editing && "ring-1 ring-foreground/15",
        isDragging && "bg-muted/40 shadow-sm ring-1 ring-foreground/15",
      )}
    >
      <div className="flex items-center gap-1 px-1.5 py-1.5">
        {dragHandle ? (
          <CurriculumDragHandle
            attributes={dragHandle.attributes}
            listeners={dragHandle.listeners}
            disabled={busy}
            label={`Reorder collection ${collection.title}`}
          />
        ) : null}
        <button
          type="button"
          aria-expanded={open}
          aria-controls={collectionPanelId}
          aria-label={
            open
              ? `Collapse ${collection.title}`
              : `Expand ${collection.title}`
          }
          onClick={onToggleOpen}
          className="flex size-9 shrink-0 items-center justify-center rounded-md text-muted-foreground touch-manipulation hover:bg-background/60 hover:text-foreground"
        >
          <ChevronRight
            className={cn(
              "size-4 transition-transform",
              open && "rotate-90",
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
            {scenarios.length} scenarios · {publishedInCollection}/
            {scenarios.length} audio
          </p>
        </div>
        <CollectionActivationSwitch
          title={collection.title}
          isActive={collection.isActive}
          pending={activationPending}
          onToggle={onToggleActive}
        />
        <div className="flex shrink-0 items-center gap-1">
          <Button
            type="button"
            variant={editing ? "secondary" : "ghost"}
            size="sm"
            className="h-7 px-2 text-xs"
            onClick={onToggleEdit}
            title="Expand and highlight this collection"
          >
            {editing ? "Done" : "Edit"}
          </Button>
        </div>
      </div>
      {open ? (
        <SortableList
          items={scenarioIds}
          disabled={busy}
          onReorder={onReorderScenarios}
          className="border-t px-2 py-1.5"
        >
          <ol id={collectionPanelId} className="flex flex-col">
            {scenarios.map((scenario, scenarioIndex) => (
              <CurriculumScenarioRow
                key={scenario.id}
                scenario={scenario}
                collectionId={collection.id}
                index={scenarioIndex}
                busy={busy}
              />
            ))}
          </ol>
        </SortableList>
      ) : null}
    </div>
  );

  if (!sortable) {
    return body();
  }

  return (
    <SortableItem id={collection.id} disabled={busy}>
      {({ setNodeRef, style, attributes, listeners, isDragging }) =>
        body(setNodeRef, style, { attributes, listeners }, isDragging)
      }
    </SortableItem>
  );
}

function CurriculumScenarioRow({
  scenario,
  collectionId,
  index,
  busy,
}: {
  scenario: ScenarioSummary;
  collectionId: string;
  index: number;
  busy: boolean;
}) {
  return (
    <SortableItem id={scenario.id} disabled={busy}>
      {({ setNodeRef, style, attributes, listeners, isDragging }) => (
        <li
          ref={setNodeRef}
          style={style}
          className={cn(
            "flex items-start gap-1 rounded px-1 py-1.5 hover:bg-background/60 sm:items-center sm:gap-2",
            isDragging && "bg-background shadow-sm ring-1 ring-foreground/10",
          )}
        >
          <CurriculumDragHandle
            attributes={attributes}
            listeners={listeners}
            disabled={busy}
            className="size-8"
            label={`Reorder scenario ${scenario.menuTitle}`}
          />
          <span className="mt-1.5 w-5 shrink-0 text-right text-[10px] text-muted-foreground sm:mt-0">
            {index + 1}
          </span>
          <Link
            href={`/content/dialogues/${collectionId}/${scenarioSlug(scenario)}`}
            className="min-w-0 flex-1 truncate text-xs hover:underline"
          >
            {scenario.menuTitle}
          </Link>
          <div className="flex shrink-0 flex-col items-end gap-1 sm:flex-row sm:items-center sm:gap-2">
            <ScenarioUpdatedLabel updatedAt={scenario.updatedAt} />
            <ScenarioReadinessChips readiness={scenario.readiness} />
          </div>
        </li>
      )}
    </SortableItem>
  );
}

function CollectionActivationSwitch({
  title,
  isActive,
  pending,
  onToggle,
}: {
  title: string;
  isActive: boolean;
  pending: boolean;
  onToggle: (isActive: boolean) => void;
}) {
  return (
    <div className="flex shrink-0 items-center gap-2 pr-1 text-xs text-muted-foreground">
      <span className="hidden sm:inline">In the app</span>
      <Switch
        checked={isActive}
        disabled={pending}
        onCheckedChange={onToggle}
        aria-label={
          isActive ? `Hide ${title} from the app` : `Show ${title} in the app`
        }
      />
    </div>
  );
}
