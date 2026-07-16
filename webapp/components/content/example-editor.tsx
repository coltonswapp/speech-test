"use client";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Plus, Trash2 } from "lucide-react";
import type { Example } from "@/lib/content/client";

export function ExampleEditor({
  examples,
  onChange,
}: {
  examples: Example[];
  onChange: (examples: Example[]) => void;
}) {
  function update(index: number, patch: Partial<Example>) {
    const next = examples.slice();
    next[index] = { ...next[index], ...patch };
    onChange(next);
  }

  function remove(index: number) {
    onChange(examples.filter((_, i) => i !== index));
  }

  function add() {
    onChange([...examples, { japanese: "", romaji: "", english: "", targetSubstring: "" }]);
  }

  return (
    <div className="flex flex-col gap-3">
      <Label>Examples</Label>
      {examples.map((example, index) => (
        <div
          key={index}
          className="flex flex-col gap-2 rounded-md border border-border/60 p-3"
        >
          <div className="flex items-center gap-2">
            <span className="text-xs text-muted-foreground">#{index + 1}</span>
            <div className="flex-1" />
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => remove(index)}
              aria-label="Remove example"
            >
              <Trash2 className="size-3.5" />
            </Button>
          </div>
          <Input
            value={example.japanese}
            onChange={(e) => update(index, { japanese: e.target.value })}
            placeholder="Japanese"
          />
          <Input
            value={example.romaji ?? ""}
            onChange={(e) => update(index, { romaji: e.target.value })}
            placeholder="Romaji"
          />
          <Input
            value={example.english}
            onChange={(e) => update(index, { english: e.target.value })}
            placeholder="English"
          />
          <Input
            value={example.targetSubstring ?? ""}
            onChange={(e) => update(index, { targetSubstring: e.target.value })}
            placeholder="Target substring (highlight)"
          />
        </div>
      ))}
      <Button variant="outline" size="sm" className="w-fit gap-2" onClick={add}>
        <Plus className="size-4" />
        Add example
      </Button>
    </div>
  );
}
