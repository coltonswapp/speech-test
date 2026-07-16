"use client";

import { Check, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { DialogueLine, GeneratedLine } from "@/lib/dialogue/types";

// Inline pending diff for a proposed LLM revision of one line: current text
// struck through, proposed text highlighted, with per-line accept/reject.
// Nothing persists until the surrounding editor's draft is saved.

function LinePreview({
  line,
  tone,
}: {
  line: DialogueLine | GeneratedLine;
  tone: "old" | "new";
}) {
  const toneClass =
    tone === "old"
      ? "text-muted-foreground line-through decoration-destructive/60"
      : "text-foreground";
  return (
    <div className={`flex flex-col text-sm ${toneClass}`}>
      <span>
        <span className="font-medium">{line.speaker}:</span> {line.japanese}
      </span>
      {(line.romaji || line.english) && (
        <span className="text-xs opacity-80">
          {[line.romaji, line.english].filter(Boolean).join(" — ")}
        </span>
      )}
      {line.grammarPointIDs && line.grammarPointIDs.length > 0 && (
        <span className="text-xs opacity-80">
          Grammar: {line.grammarPointIDs.join(", ")}
        </span>
      )}
    </div>
  );
}

export function LineRevisionDiff({
  original,
  proposed,
  onAccept,
  onReject,
}: {
  original: DialogueLine;
  proposed: GeneratedLine;
  onAccept: () => void;
  onReject: () => void;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-emerald-500/40 bg-emerald-500/5 p-3">
      <LinePreview line={original} tone="old" />
      <LinePreview line={proposed} tone="new" />
      <div className="flex gap-2">
        <Button size="sm" className="gap-1" onClick={onAccept}>
          <Check className="size-3.5" />
          Accept
        </Button>
        <Button
          size="sm"
          variant="outline"
          className="gap-1"
          onClick={onReject}
        >
          <X className="size-3.5" />
          Reject
        </Button>
      </div>
    </div>
  );
}
