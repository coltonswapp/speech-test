"use client";

import Link from "next/link";
import { cn } from "@/lib/utils";

const sections = [
  { key: "dialogues", label: "Dialogues", href: "/content/dialogues" },
  { key: "grammar", label: "Grammar", href: "/content" },
] as const;

export function SectionSwitcher({
  active,
}: {
  active: "grammar" | "dialogues";
}) {
  return (
    <div className="flex rounded-lg bg-muted p-1 text-sm">
      {sections.map((section) => (
        <Link
          key={section.key}
          href={section.href}
          className={cn(
            "flex-1 rounded-md px-3 py-1 text-center transition-colors",
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
