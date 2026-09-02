"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useDebouncedValue } from "@/lib/use-debounced-value";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";
import { contentApi } from "@/lib/content/client";
import { BatchGenerateDialog } from "@/components/content/batch-generate-dialog";

const statusLabels: Record<string, string> = {
  all: "All",
  draft: "Draft",
  needsRevision: "Needs revision",
  approved: "Approved",
};

const statusBadgeVariant: Record<
  string,
  "default" | "secondary" | "outline" | "destructive"
> = {
  draft: "outline",
  needsRevision: "destructive",
  approved: "default",
};

export function PointList({ activeId }: { activeId?: string }) {
  const [statusFilter, setStatusFilter] = useState("all");
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebouncedValue(search, 250);

  const { data, isLoading } = useQuery({
    queryKey: ["content-points", statusFilter, debouncedSearch],
    queryFn: () =>
      contentApi.listPoints({
        status: statusFilter === "all" ? undefined : statusFilter,
        search: debouncedSearch || undefined,
      }),
  });

  const { data: allPointsData } = useQuery({
    queryKey: ["content-points", "all"],
    queryFn: () => contentApi.listPoints(),
  });

  const points = data?.points ?? [];

  return (
    <div className="flex w-80 shrink-0 flex-col gap-3 border-r border-border/60 pr-4">
      <div className="flex items-center justify-between gap-2">
      </div>
      <BatchGenerateDialog points={allPointsData?.points ?? []} />
      <Input
        placeholder="Search points…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />

      <Tabs
        value={statusFilter}
        onValueChange={(value) => {
          if (value) setStatusFilter(value);
        }}
      >
        <TabsList className="w-full">
          {Object.entries(statusLabels).map(([key, label]) => (
            <TabsTrigger key={key} value={key} className="flex-1 text-xs">
              {label}
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>

      <ScrollArea className="flex-1">
        <div className="flex flex-col gap-1">
          {isLoading &&
            Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-12 w-full rounded-md" />
            ))}

          {!isLoading && points.length === 0 && (
            <p className="px-2 py-4 text-sm text-muted-foreground">
              No points match.
            </p>
          )}

          {points.map((point) => (
            <Link
              key={point.id}
              href={`/content/${point.id}`}
              className={cn(
                "flex items-center justify-between gap-2 rounded-md px-3 py-2 text-sm transition-colors",
                point.id === activeId
                  ? "bg-accent text-accent-foreground"
                  : "hover:bg-accent/50"
              )}
            >
              <div className="flex min-w-0 flex-col">
                <span className="truncate font-medium">{point.title}</span>
                <span className="truncate text-xs text-muted-foreground">
                  {point.id}
                </span>
              </div>
              <Badge
                variant={statusBadgeVariant[point.status]}
                className="shrink-0"
              >
                {statusLabels[point.status]}
              </Badge>
            </Link>
          ))}
        </div>
      </ScrollArea>
    </div>
  );
}
