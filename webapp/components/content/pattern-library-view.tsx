"use client";

import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { SectionSwitcher } from "@/components/content/section-switcher";
import {
  contentApi,
  type TeachingPatternRow,
} from "@/lib/content/client";
import { useDebouncedValue } from "@/lib/use-debounced-value";
import { cn } from "@/lib/utils";

const CATEGORY_ORDER = [
  "particle",
  "copula",
  "existence",
  "desire",
  "request",
  "obligation",
  "permission",
  "progressive",
  "experience",
  "comparison",
  "conjunction",
  "question",
  "adverb",
  "adjective",
  "other",
] as const;

function matchesSearch(pattern: TeachingPatternRow, search: string): boolean {
  const needle = search.toLowerCase();
  return (
    pattern.id.toLowerCase().includes(needle) ||
    pattern.form.toLowerCase().includes(needle) ||
    pattern.gloss.toLowerCase().includes(needle) ||
    pattern.category.toLowerCase().includes(needle)
  );
}

function statusVariant(
  status: string
): "default" | "secondary" | "outline" | "destructive" {
  switch (status) {
    case "live":
      return "default";
    case "tagged":
      return "secondary";
    case "planned":
      return "outline";
    default:
      return "outline";
  }
}

export function PatternLibraryView() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebouncedValue(search, 250);

  const { data, isLoading } = useQuery({
    queryKey: ["teaching-patterns"],
    queryFn: contentApi.listPatterns,
  });

  const importMutation = useMutation({
    mutationFn: contentApi.importPatterns,
    onSuccess: (result) => {
      toast.success(
        `Imported ${result.inserted} patterns (${result.skipped} already present)`
      );
      queryClient.invalidateQueries({ queryKey: ["teaching-patterns"] });
    },
    onError: (err: Error) => {
      toast.error(err.message || "Import failed");
    },
  });

  const patterns = useMemo(() => {
    return (data?.patterns ?? []).filter((pattern) => {
      if (debouncedSearch && !matchesSearch(pattern, debouncedSearch)) {
        return false;
      }
      return true;
    });
  }, [data, debouncedSearch]);

  const grouped = useMemo(() => {
    const map = new Map<string, TeachingPatternRow[]>();
    for (const pattern of patterns) {
      const list = map.get(pattern.category) ?? [];
      list.push(pattern);
      map.set(pattern.category, list);
    }
    for (const list of map.values()) {
      list.sort(
        (a, b) => a.orderIndex - b.orderIndex || a.id.localeCompare(b.id)
      );
    }
    const known = CATEGORY_ORDER.filter((cat) => map.has(cat));
    const extras = [...map.keys()]
      .filter((cat) => !(CATEGORY_ORDER as readonly string[]).includes(cat))
      .sort();
    return [...known, ...extras].map((category) => ({
      category,
      patterns: map.get(category) ?? [],
    }));
  }, [patterns]);

  const empty = !isLoading && (data?.patterns.length ?? 0) === 0;

  const statusCounts = useMemo(() => {
    const counts = new Map<string, number>();
    for (const pattern of data?.patterns ?? []) {
      counts.set(pattern.status, (counts.get(pattern.status) ?? 0) + 1);
    }
    return [...counts.entries()].sort(([a], [b]) => a.localeCompare(b));
  }, [data]);


  return (
    <div className="flex flex-1 flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <SectionSwitcher active="patterns" />
          {data && (
            <p className="text-sm text-muted-foreground">
              {data.patterns.length} patterns
              {debouncedSearch
                ? ` · ${patterns.length} match`
                : ""}
            </p>
          )}
        </div>
        <div className="flex items-center gap-2">
          <Input
            placeholder="Search patterns…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-56"
          />
          <Button
            onClick={() => importMutation.mutate()}
            disabled={importMutation.isPending}
          >
            {importMutation.isPending ? "Importing…" : "Import N5 seed"}
          </Button>
        </div>
      </div>

      {data && data.patterns.length > 0 && (
        <div className="flex flex-wrap gap-2">
          <Badge variant="secondary">{data.patterns.length} total</Badge>
          {statusCounts.map(([status, count]) => (
            <Badge key={status} variant={statusVariant(status)} className="capitalize">
              {status} {count}
            </Badge>
          ))}
          <Badge variant="outline">
            {data.patterns.filter((p) => p.linkedScenarioCount > 0).length} linked
          </Badge>
        </div>
      )}

      {isLoading && (
        <div className="flex flex-col gap-2 rounded-md border p-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-10 w-full rounded-md" />
          ))}
        </div>
      )}

      {!isLoading && empty && (
        <div className="flex flex-col items-center gap-3 rounded-md border border-dashed px-6 py-16 text-center">
          <p className="text-sm text-muted-foreground">
            No teaching patterns yet. Import the curated N5 seed to populate
            the coverage map.
          </p>
          <Button
            onClick={() => importMutation.mutate()}
            disabled={importMutation.isPending}
          >
            {importMutation.isPending ? "Importing…" : "Import N5 seed"}
          </Button>
        </div>
      )}

      {!isLoading && !empty && patterns.length === 0 && (
        <p className="px-4 py-8 text-center text-sm text-muted-foreground">
          No patterns match.
        </p>
      )}

      {!isLoading &&
        grouped.map(({ category, patterns: group }) => (
          <section key={category} className="flex flex-col gap-2">
            <div className="flex items-center gap-2 px-1">
              <h2 className="text-sm font-medium capitalize">{category}</h2>
              <span className="text-xs text-muted-foreground">
                {group.length}
              </span>
            </div>
            <div className="flex flex-col divide-y divide-border/60 rounded-md border">
              {group.map((pattern) => (
                <div
                  key={pattern.id}
                  className={cn(
                    "flex flex-wrap items-center gap-2 px-4 py-3",
                    pattern.linkedScenarioCount === 0 && "bg-muted/20"
                  )}
                >
                  <span className="min-w-[8rem] font-medium tracking-tight">
                    {pattern.form}
                  </span>
                  <span className="min-w-0 flex-1 truncate text-sm text-muted-foreground">
                    {pattern.gloss}
                  </span>
                  <Badge variant="secondary" className="text-[10px]">
                    N{pattern.jlptBand}
                  </Badge>
                  <Badge
                    variant={statusVariant(pattern.status)}
                    className="text-[10px] capitalize"
                  >
                    {pattern.status}
                  </Badge>
                  <Badge
                    variant={
                      pattern.linkedScenarioCount === 0
                        ? "outline"
                        : "secondary"
                    }
                    className="text-[10px] tabular-nums"
                  >
                    {pattern.linkedScenarioCount === 0
                      ? "0 scenarios"
                      : `${pattern.linkedScenarioCount} scenario${
                          pattern.linkedScenarioCount === 1 ? "" : "s"
                        }`}
                  </Badge>
                </div>
              ))}
            </div>
          </section>
        ))}
    </div>
  );
}
