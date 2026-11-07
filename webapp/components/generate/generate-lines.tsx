"use client";

import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { GripVertical, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { VoiceSelect } from "@/components/tts/voice-select";
import { GENERATE_MAX_LINES } from "@/lib/generate/types";
import { cn } from "@/lib/utils";

export type DraftLine = {
  id: string;
  text: string;
  voice: string;
  delivery: string;
  pauseAfterSeconds: number;
};

export function newDraftLine(voice: string): DraftLine {
  return {
    id:
      typeof crypto !== "undefined" && crypto.randomUUID
        ? crypto.randomUUID()
        : `line-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    text: "",
    voice,
    delivery: "",
    pauseAfterSeconds: 0.4,
  };
}

export function GenerateLines({
  lines,
  onChange,
  disabled,
}: {
  lines: DraftLine[];
  onChange: (lines: DraftLine[]) => void;
  disabled?: boolean;
}) {
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );
  const multi = lines.length > 1;

  const update = (id: string, patch: Partial<DraftLine>) => {
    onChange(lines.map((line) => (line.id === id ? { ...line, ...patch } : line)));
  };

  const onDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const oldIndex = lines.findIndex((line) => line.id === active.id);
    const newIndex = lines.findIndex((line) => line.id === over.id);
    if (oldIndex < 0 || newIndex < 0) return;
    onChange(arrayMove(lines, oldIndex, newIndex));
  };

  return (
    <div className="flex flex-col gap-3">
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
        <SortableContext items={lines.map((line) => line.id)} strategy={verticalListSortingStrategy}>
          {lines.map((line, index) => (
            <SortableLine
              key={line.id}
              line={line}
              index={index}
              total={lines.length}
              multi={multi}
              disabled={disabled}
              onChange={(patch) => update(line.id, patch)}
              onRemove={() => onChange(lines.filter((item) => item.id !== line.id))}
            />
          ))}
        </SortableContext>
      </DndContext>
      <div>
        <Button
          type="button"
          variant="outline"
          disabled={disabled || lines.length >= GENERATE_MAX_LINES}
          onClick={() =>
            onChange([
              ...lines,
              newDraftLine(lines[lines.length - 1]?.voice ?? "Kore"),
            ])
          }
        >
          <Plus className="size-4" />
          Add line
        </Button>
      </div>
    </div>
  );
}

function SortableLine({
  line,
  index,
  total,
  multi,
  disabled,
  onChange,
  onRemove,
}: {
  line: DraftLine;
  index: number;
  total: number;
  multi: boolean;
  disabled?: boolean;
  onChange: (patch: Partial<DraftLine>) => void;
  onRemove: () => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: line.id, disabled: !multi || disabled });
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={cn(
        "rounded-xl ring-1 ring-foreground/10",
        isDragging && "bg-muted/40",
      )}
    >
      <div className="flex items-start gap-2 p-3 sm:p-4">
        {multi ? (
          <button
            type="button"
            className="mt-1 flex size-9 shrink-0 cursor-grab items-center justify-center rounded-md text-muted-foreground touch-manipulation hover:bg-muted hover:text-foreground active:cursor-grabbing disabled:opacity-40"
            aria-label={`Reorder line ${index + 1}`}
            disabled={disabled}
            {...attributes}
            {...listeners}
          >
            <GripVertical className="size-4" />
          </button>
        ) : null}
        <div className="min-w-0 flex-1 space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-sm font-medium">
              {multi ? `Line ${index + 1}` : "Text"}
            </p>
            {multi ? (
              <Button
                type="button"
                variant="ghost"
                size="sm"
                disabled={disabled}
                onClick={onRemove}
                aria-label={`Remove line ${index + 1}`}
              >
                <Trash2 className="size-4" />
                Remove
              </Button>
            ) : null}
          </div>
          <Textarea
            value={line.text}
            disabled={disabled}
            placeholder={multi ? "Spoken text for this line" : "Type what you want spoken"}
            onChange={(event) => onChange({ text: event.target.value })}
            aria-label={multi ? `Line ${index + 1} text` : "Text to speak"}
          />
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label htmlFor={`voice-${line.id}`}>Voice</Label>
              <VoiceSelect
                provider="gemini"
                value={line.voice}
                onChange={(voice) => onChange({ voice })}
                className="w-full min-w-0"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor={`delivery-${line.id}`}>Delivery (optional)</Label>
              <Input
                id={`delivery-${line.id}`}
                value={line.delivery}
                disabled={disabled}
                placeholder="[softly] or [laughs]"
                onChange={(event) => onChange({ delivery: event.target.value })}
              />
            </div>
          </div>
          {multi && index < total - 1 ? (
            <div className="flex max-w-xs items-center gap-2">
              <Label htmlFor={`pause-${line.id}`} className="whitespace-nowrap">
                Pause after
              </Label>
              <Input
                id={`pause-${line.id}`}
                type="number"
                min={0}
                max={5}
                step={0.1}
                disabled={disabled}
                value={line.pauseAfterSeconds}
                onChange={(event) =>
                  onChange({
                    pauseAfterSeconds: Number(event.target.value) || 0,
                  })
                }
                className="w-24"
              />
              <span className="text-xs text-muted-foreground">seconds</span>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}
