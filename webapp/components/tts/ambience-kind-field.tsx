"use client";

import { useEffect, useId, useState } from "react";
import { Input } from "@/components/ui/input";
import {
  AMBIENCE_KIND_LABELS,
  AMBIENCE_KINDS,
  ambienceKindLabel,
  normalizeAmbienceKind,
} from "@/lib/tts/ambience";
import { cn } from "@/lib/utils";

export function AmbienceKindField({
  id,
  value,
  onChange,
  compact = false,
}: {
  id?: string;
  value: string;
  onChange: (kind: string) => void;
  compact?: boolean;
}) {
  const generatedId = useId();
  const inputId = id ?? generatedId;
  const listId = `${inputId}-presets`;
  const [draft, setDraft] = useState(ambienceKindLabel(value));

  useEffect(() => {
    setDraft(ambienceKindLabel(value));
  }, [value]);

  function commit(raw: string) {
    const next = normalizeAmbienceKind(raw);
    setDraft(ambienceKindLabel(next));
    if (next !== value) onChange(next);
  }

  return (
    <div className="flex flex-col gap-2">
      <Input
        id={inputId}
        value={draft}
        placeholder="Cafe, rain, office…"
        list={listId}
        autoComplete="off"
        onChange={(event) => {
          const next = event.target.value;
          setDraft(next);
          onChange(normalizeAmbienceKind(next));
        }}
        onBlur={() => commit(draft)}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault();
            commit(draft);
          }
        }}
      />
      <datalist id={listId}>
        {AMBIENCE_KINDS.map((kind) => (
          <option key={kind} value={AMBIENCE_KIND_LABELS[kind]} />
        ))}
      </datalist>
      {compact ? null : (
        <div className="flex flex-wrap gap-1">
          {AMBIENCE_KINDS.map((kind) => (
            <button
              key={kind}
              type="button"
              className={cn(
                "rounded-full border px-2 py-0.5 text-xs transition-colors",
                value === kind
                  ? "border-foreground bg-muted text-foreground"
                  : "border-border text-muted-foreground hover:border-foreground/50 hover:text-foreground"
              )}
              onClick={() => commit(kind)}
            >
              {AMBIENCE_KIND_LABELS[kind]}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
