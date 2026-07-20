"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useDebouncedValue } from "@/lib/use-debounced-value";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";
import { contentApi, type CoveragePoint } from "@/lib/content/client";
import { scenarioSlug } from "@/lib/dialogue/client";
import { SectionSwitcher } from "@/components/content/section-switcher";

const coverageFilters = {
  all: "All",
  covered: "Covered",
  uncovered: "Uncovered",
} as const;

type CoverageFilter = keyof typeof coverageFilters;

function matchesSearch(point: CoveragePoint, search: string): boolean {
  const needle = search.toLowerCase();
  return (
    point.id.toLowerCase().includes(needle) ||
    point.title.toLowerCase().includes(needle) ||
    (point.pattern ?? "").toLowerCase().includes(needle) ||
    point.headlineEnglish.toLowerCase().includes(needle)
  );
}

export function CoverageView() {
  const [filter, setFilter] = useState<CoverageFilter>("all");
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebouncedValue(search, 250);

  const { data, isLoading } = useQuery({
    queryKey: ["grammar-coverage"],
    queryFn: contentApi.getCoverage,
  });

  const points = (data?.points ?? []).filter((point) => {
    if (filter === "covered" && point.coverage.length === 0) return false;
    if (filter === "uncovered" && point.coverage.length > 0) return false;
    if (debouncedSearch && !matchesSearch(point, debouncedSearch)) return false;
    return true;
  });

  return (
    <div className="flex flex-1 flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <SectionSwitcher active="coverage" />
          {data && (
            <p className="text-sm text-muted-foreground">
              {data.totals.coveredCount} of {data.totals.pointCount} points
              covered across {data.totals.scenarioCount} scenarios
            </p>
          )}
        </div>
        <div className="flex items-center gap-2">
          <Input
            placeholder="Search points…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-56"
          />
          <Tabs
            value={filter}
            onValueChange={(value) => {
              if (value) setFilter(value as CoverageFilter);
            }}
          >
            <TabsList>
              {Object.entries(coverageFilters).map(([key, label]) => (
                <TabsTrigger key={key} value={key} className="text-xs">
                  {label}
                  {data && key === "uncovered" && (
                    <span className="ml-1 text-muted-foreground">
                      {data.totals.uncoveredCount}
                    </span>
                  )}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
        </div>
      </div>

      {data && data.unknownTags.length > 0 && (
        <div className="rounded-md border border-destructive/40 bg-destructive/5 px-4 py-3 text-sm">
          <p className="font-medium">
            {data.unknownTags.length} tag
            {data.unknownTags.length === 1 ? "" : "s"} reference grammar points
            that don&apos;t exist in the catalog:
          </p>
          <p className="mt-1 text-muted-foreground">
            {data.unknownTags
              .map(({ tag, scenarioIds }) => `${tag} (${scenarioIds.join(", ")})`)
              .join(" · ")}
          </p>
        </div>
      )}

      <div className="flex flex-col divide-y divide-border/60 rounded-md border">
        {isLoading &&
          Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="p-3">
              <Skeleton className="h-10 w-full rounded-md" />
            </div>
          ))}

        {!isLoading && points.length === 0 && (
          <p className="px-4 py-8 text-center text-sm text-muted-foreground">
            No points match.
          </p>
        )}

        {points.map((point) => (
          <div
            key={point.id}
            className={cn(
              "flex flex-col gap-2 px-4 py-3",
              point.coverage.length === 0 && "bg-muted/30"
            )}
          >
            <div className="flex flex-wrap items-center gap-2">
              <span className="w-10 shrink-0 text-xs tabular-nums text-muted-foreground">
                {point.orderIndex}
              </span>
              <Link
                href={`/content/${point.id}`}
                className="font-medium hover:underline"
              >
                {point.pattern ?? point.title}
              </Link>
              <span className="truncate text-sm text-muted-foreground">
                {point.headlineEnglish}
              </span>
              <span className="flex-1" />
              {point.status !== "approved" && (
                <Badge variant="outline">{point.status}</Badge>
              )}
              <Badge
                variant={point.coverage.length === 0 ? "destructive" : "secondary"}
              >
                {point.coverage.length === 0
                  ? "uncovered"
                  : `${point.coverage.length} scenario${
                      point.coverage.length === 1 ? "" : "s"
                    }`}
              </Badge>
            </div>

            {point.coverage.length > 0 && (
              <div className="ml-12 flex flex-wrap gap-1.5">
                {point.coverage.map((ref) => (
                  <Link
                    key={ref.scenarioId}
                    href={`/content/dialogues/${ref.collectionId}/${scenarioSlug(
                      { id: ref.scenarioId, collectionId: ref.collectionId }
                    )}`}
                    className="inline-flex items-center gap-1.5 rounded-full border bg-background px-2.5 py-1 text-xs transition-colors hover:bg-accent"
                    title={
                      ref.taggedLineCount > 0
                        ? `${ref.taggedLineCount} tagged line${
                            ref.taggedLineCount === 1 ? "" : "s"
                          }`
                        : "Tagged at scenario level only"
                    }
                  >
                    {ref.jlptLevel != null && (
                      <span className="font-medium text-muted-foreground">
                        N{ref.jlptLevel}
                      </span>
                    )}
                    <span className="text-muted-foreground">
                      {ref.collectionTitle}
                    </span>
                    <span>·</span>
                    <span>{ref.menuTitle}</span>
                    {ref.taggedLineCount === 0 && (
                      <span className="text-amber-600 dark:text-amber-400">
                        no lines
                      </span>
                    )}
                  </Link>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
