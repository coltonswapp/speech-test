"use client";

import Link from "next/link";
import { cn } from "@/lib/utils";

const sections = [
  { key: "dialogues", label: "Dialogues", href: "/content/dialogues" },
  { key: "curriculum", label: "Curriculum", href: "/content/curriculum" },
  { key: "grammar", label: "Grammar", href: "/content" },
  { key: "patterns", label: "Patterns", href: "/content/patterns" },
  { key: "coverage", label: "Coverage", href: "/content/coverage" },
] as const;

export function SectionSwitcher({
  active,
}: {
  active: "grammar" | "dialogues" | "coverage" | "curriculum" | "patterns";
}) {
  return (
    <div className="flex rounded-lg bg-muted p-1 text-sm">
      {sections.map((section) => (
        <Link
          key={section.key}
          href={section.href}
          className={cn(
            "flex-1 rounded-md px-2.5 py-1 text-center transition-colors whitespace-nowrap",
            section.key === active
              ? "bg-background font-medium shadow-sm"
              : "text-muted-foreground hover:text-foreground"
          )}
        >
          {section.label}
        </Link>
      ))}
    </div>
  );
}
