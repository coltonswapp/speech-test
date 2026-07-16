"use client";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Plus, Trash2 } from "lucide-react";
import type { UsageLadder } from "@/lib/content/client";

export function UsageLadderEditor({
  ladders,
  onChange,
}: {
  ladders: UsageLadder[];
  onChange: (ladders: UsageLadder[]) => void;
}) {
  function updateLadder(index: number, patch: Partial<UsageLadder>) {
    const next = ladders.slice();
    next[index] = { ...next[index], ...patch };
    onChange(next);
  }

  function removeLadder(index: number) {
    onChange(ladders.filter((_, i) => i !== index));
  }

  function addLadder() {
    onChange([...ladders, { label: "", levels: [{ japanese: "", register: "Casual" }] }]);
  }

  function updateLevel(
    ladderIndex: number,
    levelIndex: number,
    patch: Partial<UsageLadder["levels"][number]>
  ) {
    const ladder = ladders[ladderIndex];
    const levels = ladder.levels.slice();
    levels[levelIndex] = { ...levels[levelIndex], ...patch };
    updateLadder(ladderIndex, { levels });
  }

  function addLevel(ladderIndex: number) {
    const ladder = ladders[ladderIndex];
    updateLadder(ladderIndex, {
      levels: [...ladder.levels, { japanese: "", register: "" }],
    });
  }

  function removeLevel(ladderIndex: number, levelIndex: number) {
    const ladder = ladders[ladderIndex];
    updateLadder(ladderIndex, {
      levels: ladder.levels.filter((_, i) => i !== levelIndex),
    });
  }

  return (
    <div className="flex flex-col gap-3">
      <Label>Usage ladders</Label>
      {ladders.map((ladder, ladderIndex) => (
        <div
          key={ladderIndex}
          className="flex flex-col gap-2 rounded-md border border-border/60 p-3"
        >
          <div className="flex items-center gap-2">
            <Input
              value={ladder.label}
              onChange={(e) =>
                updateLadder(ladderIndex, { label: e.target.value })
              }
              placeholder="Label"
              className="flex-1"
            />
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => removeLadder(ladderIndex)}
              aria-label="Remove ladder"
            >
              <Trash2 className="size-3.5" />
            </Button>
          </div>
          {ladder.levels.map((level, levelIndex) => (
            <div key={levelIndex} className="flex items-center gap-2 pl-4">
              <Input
                value={level.japanese}
                onChange={(e) =>
                  updateLevel(ladderIndex, levelIndex, {
                    japanese: e.target.value,
                  })
                }
                placeholder="Japanese"
                className="flex-1"
              />
              <Input
                value={level.register}
                onChange={(e) =>
                  updateLevel(ladderIndex, levelIndex, {
                    register: e.target.value,
                  })
                }
                placeholder="Register"
                className="w-32"
              />
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={() => removeLevel(ladderIndex, levelIndex)}
                aria-label="Remove level"
              >
                <Trash2 className="size-3.5" />
              </Button>
            </div>
          ))}
          <Button
            variant="ghost"
            size="sm"
            className="w-fit gap-2 pl-4"
            onClick={() => addLevel(ladderIndex)}
          >
            <Plus className="size-3.5" />
            Add level
          </Button>
        </div>
      ))}
      <Button variant="outline" size="sm" className="w-fit gap-2" onClick={addLadder}>
        <Plus className="size-4" />
        Add ladder
      </Button>
    </div>
  );
}
