"use client";

import { useEffect, useState } from "react";
import { cn } from "@/lib/utils";
import { scrollToId } from "@/lib/scroll-to-id";

export type MinimapSection = {
  id: string;
  label: string;
};

/**
 * Sticky side nav for a long scrollable page of sections. Tracks which
 * section is nearest the top of the viewport via IntersectionObserver and
 * highlights it; clicking an entry smooth-scrolls to that section.
 */
export function ScenarioMinimap({ sections }: { sections: MinimapSection[] }) {
  const [activeId, setActiveId] = useState(sections[0]?.id);

  useEffect(() => {
    const elements = sections
      .map((section) => document.getElementById(section.id))
      .filter((el): el is HTMLElement => el !== null);
    if (elements.length === 0) return;

    const visible = new Map<string, number>();
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            visible.set(entry.target.id, entry.intersectionRatio);
          } else {
            visible.delete(entry.target.id);
          }
        }
        if (visible.size === 0) return;
        const topMost = sections.find((section) => visible.has(section.id));
        // React bails out of re-rendering when the value is unchanged, so no
        // need to guard against redundant sets here.
        if (topMost) setActiveId(topMost.id);
      },
      { rootMargin: "-96px 0px -70% 0px", threshold: [0, 1] },
    );

    for (const el of elements) observer.observe(el);
    return () => observer.disconnect();
  }, [sections]);

  return (
    <nav
      aria-label="Section navigation"
      className="sticky top-20 hidden h-fit w-40 shrink-0 flex-col gap-1 lg:flex"
    >
      {sections.map((section) => (
        <a
          key={section.id}
          href={`#${section.id}`}
          onClick={(e) => {
            e.preventDefault();
            scrollToId(section.id);
            setActiveId(section.id);
          }}
          className={cn(
            "rounded-md border-l-2 px-3 py-1.5 text-sm transition-colors",
            activeId === section.id
              ? "border-foreground bg-muted font-medium text-foreground"
              : "border-transparent text-muted-foreground hover:text-foreground",
          )}
        >
          {section.label}
        </a>
      ))}
    </nav>
  );
}
