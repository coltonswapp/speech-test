"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

const SETTINGS_LINKS = [
  { href: "/settings", label: "Keys", match: (path: string) => path === "/settings" },
  {
    href: "/settings/voices",
    label: "Voices",
    match: (path: string) =>
      path === "/settings/voices" || path.startsWith("/settings/voices/"),
  },
] as const;

export function SettingsSubnav() {
  const pathname = usePathname();

  return (
    <nav
      aria-label="Settings sections"
      className="flex w-fit items-center gap-1 rounded-lg bg-muted p-[3px]"
    >
      {SETTINGS_LINKS.map((link) => {
        const active = link.match(pathname);
        return (
          <Link
            key={link.href}
            href={link.href}
            className={cn(
              "inline-flex h-7 items-center rounded-md px-3 text-sm font-medium transition-colors",
              active
                ? "bg-background text-foreground shadow-sm"
                : "text-muted-foreground hover:text-foreground"
            )}
          >
            {link.label}
          </Link>
        );
      })}
    </nav>
  );
}
