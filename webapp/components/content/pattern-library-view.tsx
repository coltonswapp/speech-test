"use client";

import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import {
  contentApi,
  type TeachingPatternRow,
} from "@/lib/content/client";
import { useDebouncedValue } from "@/lib/use-debounced-value";
import { cn } from "@/lib/utils";

const CATEGORY_ORDER = [
  "copula",
  "particle",
  "existence",
  "adjective",
  "conjugation",
  "desire",
  "request_permission",
  "obligation_prohibition",
  "suggestion_invitation",
  "experience_aspect",
  "comparison",
  "time_sequence",
  "cause_reason",
  "contrast",
  "quantity_extent",
  "question_wh",
  "other",
] as const;

function matchesSearch(pattern: TeachingPatternRow, search: string): boolean {
  const needle = search.toLowerCase();
  return (
    pattern.id.toLowerCase().includes(needle) ||
    pattern.form.toLowerCase().includes(needle) ||
    pattern.gloss.toLowerCase().includes(needle) ||
    (pattern.description ?? "").toLowerCase().includes(needle) ||
    pattern.category.toLowerCase().includes(needle)
  );
}

function PatternEditor({ pattern }: { pattern: TeachingPatternRow }) {
  const queryClient = useQueryClient();
  const [description, setDescription] = useState(pattern.description ?? "");

  useEffect(() => {
    setDescription(pattern.description ?? "");
  }, [pattern.id, pattern.description]);

  const saveMutation = useMutation({
    mutationFn: () =>
      contentApi.updatePattern(pattern.id, {
        description: description.trim() ? description.trim() : null,
      }),
    onSuccess: () => {
      toast.success(`Saved ${pattern.form}`);
      queryClient.invalidateQueries({ queryKey: ["teaching-patterns"] });
    },
    onError: (err: Error) => {
      toast.error(err.message || "Save failed");
    },
  });

  const dirty =
    (description.trim() || "") !== (pattern.description?.trim() || "");

  return (
    <div className="flex w-full flex-col gap-3 border-t border-border/60 px-4 pb-4 pt-3">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`${pattern.id}-gloss`}>Gloss</Label>
        <Input
          id={`${pattern.id}-gloss`}
          value={pattern.gloss}
          readOnly
          className="bg-muted/40"
        />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`${pattern.id}-description`}>Description</Label>
        <Textarea
          id={`${pattern.id}-description`}
          rows={3}
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="1–2 sentence learner-friendly definition, e.g. Used to ask for or give permission to do something ('Is it OK if I…?' / 'You may…')."
        />
      </div>
      <div className="flex items-center justify-end">
        <Button
          size="sm"
          onClick={() => saveMutation.mutate()}
          disabled={saveMutation.isPending || !dirty}
        >
          {saveMutation.isPending ? "Saving…" : "Save"}
        </Button>
      </div>
    </div>
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
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const debouncedSearch = useDebouncedValue(search, 250);

  const { data, isLoading } = useQuery({
    queryKey: ["teaching-patterns"],
    queryFn: contentApi.listPatterns,
  });

  const importMutation = useMutation({
    mutationFn: contentApi.importPatterns,
    onSuccess: (result) => {
      const addedBit =
        result.added != null
          ? ` · added ${result.added.inserted} new / ${result.added.skipped} present`
          : "";
      toast.success(
        `Imported ${result.inserted} patterns (${result.skipped} already present)${addedBit}`
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
            {importMutation.isPending ? "Importing…" : "Import seed patterns"}
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
            No teaching patterns yet. Import the curated seed (N5 + added
            drafts) to populate the coverage map.
          </p>
          <Button
            onClick={() => importMutation.mutate()}
            disabled={importMutation.isPending}
          >
            {importMutation.isPending ? "Importing…" : "Import seed patterns"}
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
                    pattern.linkedScenarioCount === 0 && "bg-muted/20"
                  )}
                >
                  <button
                    type="button"
                    onClick={() =>
                      setSelectedId((current) =>
                        current === pattern.id ? null : pattern.id
                      )
                    }
                    className={cn(
                      "flex w-full flex-wrap items-center gap-2 px-4 py-3 text-left",
                      selectedId === pattern.id && "bg-muted/40"
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
                    {!pattern.description?.trim() && (
                      <Badge variant="outline" className="text-[10px]">
                        no description
                      </Badge>
                    )}
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
                  </button>
                  {selectedId === pattern.id && (
                    <PatternEditor pattern={pattern} />
                  )}
                </div>
              ))}
            </div>
          </section>
        ))}
    </div>
  );
}
