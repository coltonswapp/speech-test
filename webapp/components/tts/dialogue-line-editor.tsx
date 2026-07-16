"use client";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { Plus, Trash2 } from "lucide-react";

export type EditableDialogueLine = {
  id: string;
  speaker: "speaker1" | "speaker2";
  text: string;
};

const speakerColor: Record<"speaker1" | "speaker2", string> = {
  speaker1: "text-violet-400 hover:text-violet-300",
  speaker2: "text-sky-400 hover:text-sky-300",
};

export function DialogueLineEditor({
  lines,
  onChange,
  speaker1Name,
  speaker2Name,
}: {
  lines: EditableDialogueLine[];
  onChange: (lines: EditableDialogueLine[]) => void;
  speaker1Name: string;
  speaker2Name: string;
}) {
  const label = (speaker: "speaker1" | "speaker2") =>
    speaker === "speaker1"
      ? speaker1Name.trim() || "Speaker 1"
      : speaker2Name.trim() || "Speaker 2";

  function update(index: number, patch: Partial<EditableDialogueLine>) {
    const next = lines.slice();
    next[index] = { ...next[index], ...patch };
    onChange(next);
  }

  function remove(index: number) {
    onChange(lines.filter((_, i) => i !== index));
  }

  function addLine() {
    const lastSpeaker = lines[lines.length - 1]?.speaker;
    const nextSpeaker = lastSpeaker === "speaker1" ? "speaker2" : "speaker1";
    onChange([
      ...lines,
      { id: crypto.randomUUID(), speaker: nextSpeaker, text: "" },
    ]);
  }

  function toggleSpeaker(index: number, current: "speaker1" | "speaker2") {
    update(index, {
      speaker: current === "speaker1" ? "speaker2" : "speaker1",
    });
  }

  return (
    <div className="flex flex-col">
      {lines.map((line, index) => {
        const isNewSpeaker = line.speaker !== lines[index - 1]?.speaker;
        return (
          <div
            key={line.id}
            className={cn("flex items-start gap-2", isNewSpeaker ? "mt-6" : "mt-2")}
          >
            <button
              type="button"
              onClick={() => toggleSpeaker(index, line.speaker)}
              className={cn(
                "w-[6.5rem] shrink-0 pt-1.5 text-right text-xs font-semibold transition-colors",
                speakerColor[line.speaker]
              )}
              title="Click to switch speaker"
            >
              {label(line.speaker)}
            </button>
            <Textarea
              rows={1}
              value={line.text}
              onChange={(e) => update(index, { text: e.target.value })}
              placeholder="Line text…"
              className="min-h-9 flex-1 resize-none"
            />
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => remove(index)}
              aria-label="Remove line"
            >
              <Trash2 className="size-3.5" />
            </Button>
          </div>
        );
      })}

      <Button
        variant="outline"
        size="sm"
        className="mt-6 w-fit gap-2"
        onClick={addLine}
      >
        <Plus className="size-4" />
        Add line
      </Button>
    </div>
  );
}
