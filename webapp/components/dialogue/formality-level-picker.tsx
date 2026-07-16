"use client";

import { Label } from "@/components/ui/label";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  dialogueFormalityHints,
  dialogueFormalityLabels,
  dialogueFormalityLevels,
  type DialogueFormality,
} from "@/lib/dialogue/formality";
import { cn } from "@/lib/utils";

export function FormalityLevelPicker({
  value,
  onChange,
  className,
}: {
  value: DialogueFormality;
  onChange: (value: DialogueFormality) => void;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col gap-2", className)}>
      <Label>Japanese formality</Label>
      <Tabs
        value={value}
        onValueChange={(next) => {
          if (
            next &&
            dialogueFormalityLevels.includes(next as DialogueFormality)
          ) {
            onChange(next as DialogueFormality);
          }
        }}
      >
        <TabsList className="h-auto w-full flex-wrap">
          {dialogueFormalityLevels.map((level) => (
            <TabsTrigger key={level} value={level} className="text-xs">
              {dialogueFormalityLabels[level]}
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
      <p className="text-xs text-muted-foreground">
        {dialogueFormalityHints[value]}
      </p>
    </div>
  );
}
