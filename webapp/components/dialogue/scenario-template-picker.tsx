"use client";

import { useMemo, useState } from "react";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";
import {
  groupTemplatesByCollection,
  type ScenarioTemplate,
} from "@/lib/dialogue/scenario-templates";

export function ScenarioTemplatePicker({
  templates,
  onSelect,
  existingSlugs = [],
  prioritizeCollectionId,
  className,
}: {
  templates: ScenarioTemplate[];
  onSelect: (template: ScenarioTemplate) => void;
  existingSlugs?: string[];
  prioritizeCollectionId?: string;
  className?: string;
}) {
  const [search, setSearch] = useState("");

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    const matches = query
      ? templates.filter(
          (template) =>
            template.menuTitle.toLowerCase().includes(query) ||
            template.slug.toLowerCase().includes(query) ||
            template.setting.toLowerCase().includes(query) ||
            template.collectionTitle.toLowerCase().includes(query)
        )
      : templates;

    if (!prioritizeCollectionId) {
      return matches;
    }

    const preferred = matches.filter(
      (template) => template.collectionId === prioritizeCollectionId
    );
    const other = matches.filter(
      (template) => template.collectionId !== prioritizeCollectionId
    );
    return [...preferred, ...other];
  }, [templates, search, prioritizeCollectionId]);

  const groups = useMemo(
    () => groupTemplatesByCollection(filtered),
    [filtered]
  );

  const preferredCount = prioritizeCollectionId
    ? filtered.filter(
        (template) => template.collectionId === prioritizeCollectionId
      ).length
    : 0;

  return (
    <div className={cn("flex flex-col gap-2", className)}>
      <Input
        value={search}
        onChange={(event) => setSearch(event.target.value)}
        placeholder="Search scenario ideas…"
      />
      <ScrollArea className="h-full min-h-56 flex-1 rounded-md border border-border/60">
        <div className="flex flex-col gap-3 p-2">
          {filtered.length === 0 ? (
            <p className="px-2 py-3 text-sm text-muted-foreground">
              No matching scenario ideas.
            </p>
          ) : null}

          {groups.map((group, groupIndex) => (
            <div key={group.collectionTitle} className="flex flex-col gap-1">
              {groupIndex === 0 &&
              prioritizeCollectionId &&
              preferredCount > 0 ? (
                <p className="px-2 text-xs font-medium text-muted-foreground">
                  For this collection
                </p>
              ) : groupIndex === 1 &&
                prioritizeCollectionId &&
                preferredCount > 0 ? (
                <p className="px-2 pt-1 text-xs font-medium text-muted-foreground">
                  More ideas
                </p>
              ) : (
                <p className="px-2 text-xs font-medium text-muted-foreground">
                  {group.collectionTitle}
                </p>
              )}
              {group.templates.map((template) => {
                const alreadyAdded = existingSlugs.includes(template.slug);
                return (
                  <button
                    key={`${template.collectionId}/${template.slug}`}
                    type="button"
                    disabled={alreadyAdded}
                    onClick={() => onSelect(template)}
                    className={cn(
                      "flex flex-col items-start rounded-md px-2 py-2 text-left transition-colors",
                      alreadyAdded
                        ? "cursor-not-allowed opacity-50"
                        : "hover:bg-accent"
                    )}
                  >
                    <span className="text-sm font-medium">
                      {template.menuTitle}
                    </span>
                    <span className="line-clamp-2 text-xs text-muted-foreground">
                      {template.setting}
                    </span>
                    {alreadyAdded ? (
                      <span className="text-xs text-muted-foreground">
                        Already in this collection
                      </span>
                    ) : null}
                  </button>
                );
              })}
            </div>
          ))}
        </div>
      </ScrollArea>
    </div>
  );
}
