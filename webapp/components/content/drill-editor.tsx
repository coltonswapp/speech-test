"use client";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Plus, Trash2 } from "lucide-react";
import type { Drill } from "@/lib/content/client";

const DRILL_KINDS = ["precursorChoice", "contrastChoice"] as const;

export function DrillEditor({
  drills,
  onChange,
}: {
  drills: Drill[];
  onChange: (drills: Drill[]) => void;
}) {
  function update(index: number, patch: Partial<Drill>) {
    const next = drills.slice();
    next[index] = { ...next[index], ...patch };
    onChange(next);
  }

  function remove(index: number) {
    onChange(drills.filter((_, i) => i !== index));
  }

  function add() {
    onChange([
      ...drills,
      {
        kind: "precursorChoice",
        instruction: "",
        exampleJapanese: "",
        targetSubstring: "",
        english: "",
        choices: [],
        correctChoice: "",
      },
    ]);
  }

  return (
    <div className="flex flex-col gap-3">
      <Label>Drills</Label>
      {drills.map((drill, index) => (
        <div
          key={index}
          className="flex flex-col gap-2 rounded-md border border-border/60 p-3"
        >
          <div className="flex items-center gap-2">
            <select
              value={drill.kind}
              onChange={(e) => update(index, { kind: e.target.value })}
              className="rounded-md border border-border/60 bg-transparent px-2 py-1 text-sm"
            >
              {DRILL_KINDS.map((kind) => (
                <option key={kind} value={kind}>
                  {kind}
                </option>
              ))}
            </select>
            <div className="flex-1" />
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => remove(index)}
              aria-label="Remove drill"
            >
              <Trash2 className="size-3.5" />
            </Button>
          </div>
          <Input
            value={drill.instruction ?? ""}
            onChange={(e) => update(index, { instruction: e.target.value })}
            placeholder="Instruction"
          />
          <Input
            value={drill.exampleJapanese ?? ""}
            onChange={(e) => update(index, { exampleJapanese: e.target.value })}
            placeholder="Example Japanese (use ___ for blank)"
          />
          <Input
            value={drill.targetSubstring ?? ""}
            onChange={(e) => update(index, { targetSubstring: e.target.value })}
            placeholder="Target substring"
          />
          <Input
            value={drill.english ?? ""}
            onChange={(e) => update(index, { english: e.target.value })}
            placeholder="English"
          />
          {drill.kind === "contrastChoice" && (
            <Input
              value={drill.contrastLabel ?? ""}
              onChange={(e) => update(index, { contrastLabel: e.target.value })}
              placeholder="Contrast label"
            />
          )}
          <Input
            value={(drill.choices ?? []).join(", ")}
            onChange={(e) =>
              update(index, {
                choices: e.target.value
                  .split(",")
                  .map((s) => s.trim())
                  .filter(Boolean),
              })
            }
            placeholder="Choices (comma separated)"
          />
          <Input
            value={drill.correctChoice ?? ""}
            onChange={(e) => update(index, { correctChoice: e.target.value })}
            placeholder="Correct choice"
          />
        </div>
      ))}
      <Button variant="outline" size="sm" className="w-fit gap-2" onClick={add}>
        <Plus className="size-4" />
        Add drill
      </Button>
    </div>
  );
}
