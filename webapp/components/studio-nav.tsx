"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { AudioLinesIcon, BookOpenIcon, SettingsIcon } from "lucide-react";
import { cn } from "@/lib/utils";

const links = [
  { href: "/content/dialogues", activeMatch: "/content", label: "Content Studio", icon: BookOpenIcon },
  { href: "/tts", label: "TTS Studio", icon: AudioLinesIcon },
  { href: "/settings", label: "Settings", icon: SettingsIcon },
];

export function StudioNav() {
  const pathname = usePathname();

  return (
    <nav data-slot="studio-nav" className="flex items-center gap-1">
      {links.map((link) => {
        const matchBase = link.activeMatch ?? link.href;
        const active =
          matchBase === "/settings"
            ? pathname.startsWith(matchBase)
            : pathname === matchBase || pathname.startsWith(`${matchBase}/`);
        const Icon = link.icon;
        return (
          <Link
            key={link.href}
            href={link.href}
            className={cn(
              "flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
              active
                ? "bg-accent text-accent-foreground"
                : "text-muted-foreground hover:text-foreground"
            )}
          >
            <Icon data-slot="nav-icon" />
            {link.label}
          </Link>
        );
      })}
    </nav>
  );
}
