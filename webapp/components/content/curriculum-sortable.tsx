"use client";

import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DraggableAttributes,
  type DraggableSyntheticListeners,
} from "@dnd-kit/core";
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { GripVertical } from "lucide-react";
import type { CSSProperties, ReactNode } from "react";
import { cn } from "@/lib/utils";

export function useCurriculumDragSensors() {
  return useSensors(
    useSensor(PointerSensor, {
      // Small distance so clicks/taps on nearby controls still work, while
      // touch drag on phones can start after a short intentional move.
      activationConstraint: { distance: 8 },
    }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );
}

export function CurriculumDragHandle({
  attributes,
  listeners,
  disabled,
  className,
  label = "Drag to reorder",
}: {
  attributes: DraggableAttributes;
  listeners: DraggableSyntheticListeners;
  disabled?: boolean;
  className?: string;
  label?: string;
}) {
  return (
    <button
      type="button"
      className={cn(
        "flex size-9 shrink-0 cursor-grab items-center justify-center rounded-md text-muted-foreground touch-manipulation hover:bg-background/60 hover:text-foreground active:cursor-grabbing disabled:cursor-not-allowed disabled:opacity-40",
        className,
      )}
      disabled={disabled}
      aria-label={label}
      {...attributes}
      {...listeners}
    >
      <GripVertical className="size-4" />
    </button>
  );
}

type SortableRenderArgs = {
  setNodeRef: (node: HTMLElement | null) => void;
  style: CSSProperties;
  attributes: DraggableAttributes;
  listeners: DraggableSyntheticListeners;
  isDragging: boolean;
};

export function SortableItem({
  id,
  disabled,
  children,
}: {
  id: string;
  disabled?: boolean;
  children: (args: SortableRenderArgs) => ReactNode;
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id, disabled });

  const style: CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.55 : undefined,
    position: "relative",
    zIndex: isDragging ? 10 : undefined,
  };

  return children({ setNodeRef, style, attributes, listeners, isDragging });
}

/** Independent vertical sortable list (safe to nest: one DndContext per list). */
export function SortableList({
  items,
  disabled,
  onReorder,
  className,
  children,
}: {
  items: string[];
  disabled?: boolean;
  onReorder: (orderedIds: string[]) => void;
  className?: string;
  children: ReactNode;
}) {
  const sensors = useCurriculumDragSensors();

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over || active.id === over.id || disabled) return;
    const oldIndex = items.indexOf(String(active.id));
    const newIndex = items.indexOf(String(over.id));
    if (oldIndex < 0 || newIndex < 0 || oldIndex === newIndex) return;
    onReorder(arrayMove(items, oldIndex, newIndex));
  }

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCenter}
      onDragEnd={handleDragEnd}
    >
      <SortableContext
        items={items}
        strategy={verticalListSortingStrategy}
        disabled={disabled}
      >
        <div className={className}>{children}</div>
      </SortableContext>
    </DndContext>
  );
}
