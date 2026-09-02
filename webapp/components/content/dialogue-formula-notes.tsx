"use client";

import {
  DIALOGUE_FORMULA_LINES,
  DIALOGUE_FORMULA_LOCKED_AT,
} from "@/lib/dialogue/formula";

export function DialogueFormulaNotes() {
  return (
    <aside className="rounded-lg border border-border/70 bg-muted/20 px-3 py-2.5">
      <div className="mb-1.5 flex items-baseline justify-between gap-3">
        <h2 className="text-sm font-medium">Dialogue formula</h2>
        <p className="text-[11px] text-muted-foreground">
          Locked {DIALOGUE_FORMULA_LOCKED_AT}
        </p>
      </div>
      <ul className="list-disc space-y-0.5 pl-4 text-xs leading-snug text-muted-foreground">
        {DIALOGUE_FORMULA_LINES.map((line) => (
          <li key={line}>{line}</li>
        ))}
      </ul>
    </aside>
  );
}
