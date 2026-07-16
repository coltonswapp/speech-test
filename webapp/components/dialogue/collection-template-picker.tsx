"use client";

import { useMemo, useState } from "react";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";
import { collectionTemplates } from "@/lib/dialogue/scenario-templates";

export function CollectionTemplatePicker({
  onSelect,
  className,
}: {
  onSelect: (template: {
    collectionId: string;
    collectionTitle: string;
    collectionSubtitle?: string;
    sceneImage?: string;
  }) => void;
  className?: string;
}) {
  const [search, setSearch] = useState("");

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return collectionTemplates;
    return collectionTemplates.filter(
      (template) =>
        template.collectionTitle.toLowerCase().includes(query) ||
        template.collectionId.toLowerCase().includes(query) ||
        template.collectionSubtitle?.toLowerCase().includes(query)
    );
  }, [search]);

  return (
    <div className={cn("flex flex-col gap-2", className)}>
      <Input
        value={search}
        onChange={(event) => setSearch(event.target.value)}
        placeholder="Search collection ideas…"
      />
      <ScrollArea className="h-48 rounded-md border border-border/60">
        <div className="flex flex-col gap-1 p-2">
          {filtered.length === 0 ? (
            <p className="px-2 py-3 text-sm text-muted-foreground">
              No matching collection ideas.
            </p>
          ) : null}
          {filtered.map((template) => (
            <button
              key={template.collectionId}
              type="button"
              onClick={() => onSelect(template)}
              className="flex flex-col items-start rounded-md px-2 py-2 text-left hover:bg-accent"
            >
              <span className="text-sm font-medium">
                {template.collectionTitle}
              </span>
              <span className="text-xs text-muted-foreground">
                {template.collectionId} · {template.scenarioCount} scenario
                ideas
              </span>
              {template.collectionSubtitle ? (
                <span className="line-clamp-2 text-xs text-muted-foreground">
                  {template.collectionSubtitle}
                </span>
              ) : null}
            </button>
          ))}
        </div>
      </ScrollArea>
    </div>
  );
}
