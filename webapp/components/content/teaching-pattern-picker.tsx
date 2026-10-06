"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Layers, X } from "lucide-react";
import { useDebouncedValue } from "@/lib/use-debounced-value";
import {
  contentApi,
  type TeachingPatternRow,
} from "@/lib/content/client";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";

function PatternChip({
  pattern,
  id,
  onRemove,
}: {
  pattern?: TeachingPatternRow;
  id: string;
  onRemove: () => void;
}) {
  return (
    <span
      className={cn(
        "inline-flex max-w-full items-start gap-1.5 rounded-md border px-2 py-1.5",
        "border-sky-400/50 bg-sky-50 text-sky-950",
        "dark:border-sky-500/35 dark:bg-sky-950/50 dark:text-sky-50"
      )}
    >
      <Layers className="mt-0.5 size-3.5 shrink-0 text-sky-600 dark:text-sky-300" />
      <span className="flex min-w-0 flex-col gap-0.5">
        <span className="truncate font-mono text-sm font-medium leading-tight">
          {pattern?.form ?? id}
        </span>
        <span className="truncate text-[11px] leading-tight text-sky-800/80 dark:text-sky-200/80">
          {pattern?.gloss?.trim() || id}
        </span>
      </span>
      <button
        type="button"
        onClick={onRemove}
        className={cn(
          "rounded-sm p-0.5 transition-colors",
          "text-sky-700 hover:bg-sky-200/80 dark:text-sky-200 dark:hover:bg-sky-900/80"
        )}
        aria-label={`Remove ${pattern?.form ?? id}`}
      >
        <X className="size-3.5" />
      </button>
    </span>
  );
}

export function TeachingPatternPicker({
  value,
  onChange,
  label = "Pattern library",
  description,
  variant = "default",
  className,
}: {
  /** Selected teaching_pattern id, or null when unset. */
  value: string | null;
  onChange: (pattern: TeachingPatternRow | null) => void;
  label?: string;
  description?: string;
  variant?: "default" | "embedded";
  className?: string;
}) {
  const [search, setSearch] = useState("");
  const [open, setOpen] = useState(false);
  const debouncedSearch = useDebouncedValue(search, 250);

  const { data, isLoading } = useQuery({
    queryKey: ["teaching-patterns"],
    queryFn: contentApi.listPatterns,
    staleTime: 5 * 60 * 1000,
  });

  const patterns = data?.patterns ?? [];
  const patternMap = useMemo(
    () => new Map(patterns.map((pattern) => [pattern.id, pattern])),
    [patterns]
  );
  const selected = value ? patternMap.get(value) : undefined;

  const results = useMemo(() => {
    const needle = debouncedSearch.trim().toLowerCase();
    return patterns.filter((pattern) => {
      if (value && pattern.id === value) return false;
      if (!needle) return true;
      return (
        pattern.id.toLowerCase().includes(needle) ||
        pattern.form.toLowerCase().includes(needle) ||
        pattern.gloss.toLowerCase().includes(needle) ||
        pattern.category.toLowerCase().includes(needle)
      );
    });
  }, [patterns, debouncedSearch, value]);

  return (
    <div
      className={cn(
        "flex flex-col gap-2",
        variant === "default" && "rounded-md border border-border/60 p-3",
        className
      )}
    >
      <div className="flex flex-col gap-0.5">
        <span className="text-sm font-medium">{label}</span>
        {description ? (
          <span className="text-xs text-muted-foreground">{description}</span>
        ) : null}
      </div>

      {value ? (
        <div className="flex flex-wrap gap-2">
          <PatternChip
            id={value}
            pattern={selected}
            onRemove={() => onChange(null)}
          />
        </div>
      ) : (
        <p className="text-xs text-muted-foreground">No pattern linked yet.</p>
      )}

      {open ? (
        <div className="flex flex-col gap-2">
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search patterns…"
            autoFocus
          />
          <ScrollArea className="h-40 rounded-md border border-border/60">
            <div className="flex flex-col p-1">
              {isLoading && (
                <p className="px-2 py-1.5 text-xs text-muted-foreground">
                  Loading…
                </p>
              )}
              {!isLoading && results.length === 0 && (
                <p className="px-2 py-1.5 text-xs text-muted-foreground">
                  No patterns match.
                </p>
              )}
              {results.map((pattern) => (
                <button
                  key={pattern.id}
                  type="button"
                  className="rounded-md px-2 py-1.5 text-left hover:bg-muted/60"
                  onClick={() => {
                    onChange(pattern);
                    setOpen(false);
                    setSearch("");
                  }}
                >
                  <span className="block font-mono text-sm leading-tight">
                    {pattern.form}
                  </span>
                  <span className="block text-[11px] text-muted-foreground">
                    {pattern.gloss} · {pattern.id}
                  </span>
                </button>
              ))}
            </div>
          </ScrollArea>
          <button
            type="button"
            className="text-xs text-muted-foreground underline-offset-2 hover:underline"
            onClick={() => {
              setOpen(false);
              setSearch("");
            }}
          >
            Cancel
          </button>
        </div>
      ) : (
        <button
          type="button"
          className="w-fit text-xs font-medium text-sky-700 underline-offset-2 hover:underline dark:text-sky-300"
          onClick={() => setOpen(true)}
        >
          {value ? "Change pattern" : "Pick pattern"}
        </button>
      )}
    </div>
  );
}
