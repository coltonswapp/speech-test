"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { BookMarked, X } from "lucide-react";
import { useDebouncedValue } from "@/lib/use-debounced-value";
import { contentApi, type PointSummary } from "@/lib/content/client";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";

function GrammarPointChip({
  point,
  id,
  onRemove,
}: {
  point?: PointSummary;
  id: string;
  onRemove: () => void;
}) {
  return (
    <span
      className={cn(
        "inline-flex max-w-full items-start gap-1.5 rounded-md border px-2 py-1.5",
        "border-amber-400/50 bg-amber-50 text-amber-950",
        "dark:border-amber-500/35 dark:bg-amber-950/50 dark:text-amber-50"
      )}
    >
      <BookMarked className="mt-0.5 size-3.5 shrink-0 text-amber-600 dark:text-amber-300" />
      <span className="flex min-w-0 flex-col gap-0.5">
        <span className="truncate text-sm font-medium leading-tight">
          {point?.title ?? id}
        </span>
        {point?.pattern ? (
          <span className="truncate font-mono text-[11px] leading-tight text-amber-800/80 dark:text-amber-200/80">
            {point.pattern}
          </span>
        ) : (
          <span className="truncate font-mono text-[10px] leading-tight text-amber-700/70 dark:text-amber-300/70">
            {id}
          </span>
        )}
      </span>
      <button
        type="button"
        onClick={onRemove}
        className={cn(
          "rounded-sm p-0.5 transition-colors",
          "text-amber-700 hover:bg-amber-200/80 dark:text-amber-200 dark:hover:bg-amber-900/80"
        )}
        aria-label={`Remove ${point?.title ?? id}`}
      >
        <X className="size-3.5" />
      </button>
    </span>
  );
}

export function GrammarPointPicker({
  value,
  onChange,
  label = "Grammar points",
  description,
  multiple = true,
  variant = "default",
  className,
}: {
  value: string[];
  onChange: (ids: string[]) => void;
  label?: string;
  description?: string;
  multiple?: boolean;
  variant?: "default" | "embedded";
  className?: string;
}) {
  const [search, setSearch] = useState("");
  const [open, setOpen] = useState(false);
  const debouncedSearch = useDebouncedValue(search, 250);

  const { data: allData } = useQuery({
    queryKey: ["content-points", "all-labels"],
    queryFn: () => contentApi.listPoints(),
    staleTime: 5 * 60 * 1000,
  });

  const { data: searchData, isLoading } = useQuery({
    queryKey: ["content-points", "picker-search", debouncedSearch],
    queryFn: () =>
      contentApi.listPoints({
        search: debouncedSearch || undefined,
      }),
    enabled: open,
  });

  const pointMap = new Map(
    (allData?.points ?? []).map((point) => [point.id, point])
  );

  const source = debouncedSearch
    ? (searchData?.points ?? [])
    : (allData?.points ?? []);
  const results = source.filter((point) => !value.includes(point.id));

  function add(id: string) {
    if (multiple) {
      onChange([...value, id]);
    } else {
      onChange([id]);
      setOpen(false);
    }
    setSearch("");
  }

  function remove(id: string) {
    onChange(value.filter((item) => item !== id));
  }

  return (
    <div
      className={cn(
        "flex flex-col gap-2.5 rounded-lg border",
        "border-amber-400/30 bg-amber-50/70",
        "dark:border-amber-500/25 dark:bg-amber-950/20",
        variant === "embedded" ? "p-2.5" : "p-3",
        className
      )}
    >
      {label ? (
        <div className="flex flex-col gap-1">
          <div className="flex items-center gap-2">
            <span
              className={cn(
                "inline-flex items-center justify-center rounded-md",
                "bg-amber-200/70 text-amber-900",
                "dark:bg-amber-900/60 dark:text-amber-100",
                variant === "embedded" ? "size-6" : "size-7"
              )}
            >
              <BookMarked
                className={variant === "embedded" ? "size-3.5" : "size-4"}
              />
            </span>
            <span
              className={cn(
                "font-semibold tracking-tight text-amber-950 dark:text-amber-50",
                variant === "embedded" ? "text-xs" : "text-sm"
              )}
            >
              {label}
            </span>
          </div>
          {description ? (
            <p className="pl-9 text-xs leading-relaxed text-amber-900/70 dark:text-amber-100/70">
              {description}
            </p>
          ) : null}
        </div>
      ) : null}

      {value.length > 0 ? (
        <div className="flex flex-wrap gap-2">
          {value.map((id) => (
            <GrammarPointChip
              key={id}
              id={id}
              point={pointMap.get(id)}
              onRemove={() => remove(id)}
            />
          ))}
        </div>
      ) : (
        <p className="rounded-md border border-dashed border-amber-400/40 px-2.5 py-2 text-xs text-amber-900/65 dark:border-amber-500/30 dark:text-amber-100/65">
          No grammar points linked yet.
        </p>
      )}

      <div className="relative">
        <Input
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          placeholder={
            multiple
              ? "Search grammar points to add…"
              : "Search grammar points…"
          }
          className={cn(
            "border-amber-300/60 bg-white/80 placeholder:text-amber-900/45",
            "dark:border-amber-500/30 dark:bg-amber-950/30 dark:placeholder:text-amber-100/45"
          )}
        />

        {open ? (
          <>
            <div
              className="fixed inset-0 z-40"
              onClick={() => setOpen(false)}
              aria-hidden
            />
            <div
              className={cn(
                "absolute top-full z-50 mt-1 w-full rounded-md border shadow-md",
                "border-amber-300/60 bg-popover",
                "dark:border-amber-500/30"
              )}
            >
              <ScrollArea className="h-64">
                <div className="p-1">
                  {isLoading ? (
                    <p className="px-2 py-2 text-xs text-muted-foreground">
                      Searching…
                    </p>
                  ) : null}
                  {!isLoading && results.length === 0 ? (
                    <p className="px-2 py-2 text-xs text-muted-foreground">
                      No matching points.
                    </p>
                  ) : null}
                  {results.map((point) => (
                    <button
                      key={point.id}
                      type="button"
                      className={cn(
                        "flex w-full flex-col items-start rounded-md px-2 py-2 text-left",
                        "hover:bg-amber-100/80 dark:hover:bg-amber-900/40"
                      )}
                      onClick={() => add(point.id)}
                    >
                      <span className="text-sm font-medium text-foreground">
                        {point.title}
                      </span>
                      <span className="font-mono text-xs text-amber-800/75 dark:text-amber-200/75">
                        {point.pattern ?? point.id}
                      </span>
                    </button>
                  ))}
                </div>
              </ScrollArea>
            </div>
          </>
        ) : null}
      </div>
    </div>
  );
}
