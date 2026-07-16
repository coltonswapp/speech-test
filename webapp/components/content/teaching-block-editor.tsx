"use client";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Plus, Trash2 } from "lucide-react";
import type { TeachingBlock } from "@/lib/content/client";

export function TeachingBlockEditor({
  label,
  blocks,
  onChange,
}: {
  label: string;
  blocks: TeachingBlock[];
  onChange: (blocks: TeachingBlock[]) => void;
}) {
  function update(index: number, patch: Partial<TeachingBlock>) {
    const next = blocks.slice();
    next[index] = { ...next[index], ...patch };
    onChange(next);
  }

  function remove(index: number) {
    onChange(blocks.filter((_, i) => i !== index));
  }

  function add() {
    onChange([...blocks, { title: "", body: "" }]);
  }

  return (
    <div className="flex flex-col gap-3">
      <Label>{label}</Label>
      {blocks.map((block, index) => (
        <div
          key={index}
          className="flex flex-col gap-2 rounded-md border border-border/60 p-3"
        >
          <div className="flex items-center gap-2">
            <Input
              value={block.title}
              onChange={(e) => update(index, { title: e.target.value })}
              placeholder="Title"
              className="flex-1"
            />
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => remove(index)}
              aria-label="Remove block"
            >
              <Trash2 className="size-3.5" />
            </Button>
          </div>
          <Textarea
            rows={3}
            value={block.body}
            onChange={(e) => update(index, { body: e.target.value })}
            placeholder="Body"
          />
        </div>
      ))}
      <Button variant="outline" size="sm" className="w-fit gap-2" onClick={add}>
        <Plus className="size-4" />
        Add block
      </Button>
    </div>
  );
}
