"use client";

import { Label } from "@/components/ui/label";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  dialogueDifficultyHints,
  dialogueDifficultyLabels,
  dialogueDifficultyLevels,
  type DialogueDifficulty,
} from "@/lib/dialogue/difficulty";
import { cn } from "@/lib/utils";

export function DifficultyLevelPicker({
  value,
  onChange,
  className,
}: {
  value: DialogueDifficulty;
  onChange: (value: DialogueDifficulty) => void;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col gap-2", className)}>
      <Label>Japanese difficulty</Label>
      <Tabs
        value={value}
        onValueChange={(next) => {
          if (
            next &&
            dialogueDifficultyLevels.includes(next as DialogueDifficulty)
          ) {
            onChange(next as DialogueDifficulty);
          }
        }}
      >
        <TabsList className="h-auto w-full flex-wrap">
          {dialogueDifficultyLevels.map((level) => (
            <TabsTrigger key={level} value={level} className="text-xs">
              {dialogueDifficultyLabels[level]}
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
      <p className="text-xs text-muted-foreground">
        {dialogueDifficultyHints[value]}
      </p>
    </div>
  );
}
