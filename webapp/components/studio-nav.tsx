"use client";

import { useLayoutEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  AudioLinesIcon,
  BookOpenIcon,
  ChevronDownIcon,
  GraduationCapIcon,
  LayersIcon,
  MessagesSquareIcon,
  PieChartIcon,
  SettingsIcon,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useDesignMode } from "@/components/design-mode-provider";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

const CONTENT_SECTIONS = [
  "/content/dialogues",
  "/content/curriculum",
  "/content/patterns",
  "/content/coverage",
] as const;

type NavLink = {
  href: string;
  label: string;
  icon: LucideIcon;
};

const links: NavLink[] = [
  { href: "/content/dialogues", label: "Dialogues", icon: MessagesSquareIcon },
  { href: "/content/curriculum", label: "Curriculum", icon: GraduationCapIcon },
  { href: "/content", label: "Grammar", icon: BookOpenIcon },
  { href: "/content/patterns", label: "Patterns", icon: LayersIcon },
  { href: "/content/coverage", label: "Coverage", icon: PieChartIcon },
  { href: "/tts", label: "TTS Studio", icon: AudioLinesIcon },
  { href: "/settings", label: "Settings", icon: SettingsIcon },
];

const pillClassName =
  "flex shrink-0 items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium whitespace-nowrap transition-colors";

function matchesPath(pathname: string, href: string): boolean {
  if (href === "/content") {
    if (pathname === "/content") return true;
    if (!pathname.startsWith("/content/")) return false;
    return !CONTENT_SECTIONS.some(
      (section) => pathname === section || pathname.startsWith(`${section}/`),
    );
  }
  return pathname === href || pathname.startsWith(`${href}/`);
}

function computeVisibleIndices(
  itemWidths: number[],
  moreWidth: number,
  gap: number,
  containerWidth: number,
  activeIndex: number,
): { visible: number[]; overflow: number[] } {
  const n = itemWidths.length;
  const all = Array.from({ length: n }, (_, i) => i);
  const sum = (idxs: number[]) => {
    if (idxs.length === 0) return 0;
    return idxs.reduce((s, i) => s + itemWidths[i], 0) + gap * Math.max(0, idxs.length - 1);
  };

  if (sum(all) <= containerWidth + 0.5) {
    return { visible: all, overflow: [] };
  }

  const moreSpace = gap + moreWidth;
  const canFit = (idxs: number[]) => sum(idxs) + moreSpace <= containerWidth + 0.5;

  const prefix: number[] = [];
  for (let i = 0; i < n; i++) {
    if (canFit([...prefix, i])) prefix.push(i);
    else break;
  }

  let visible = prefix;
  if (activeIndex >= 0 && !prefix.includes(activeIndex)) {
    const next = [...prefix];
    while (next.length > 0 && !canFit([...next, activeIndex])) {
      next.pop();
    }
    next.push(activeIndex);
    visible = next;
  }

  const visibleSet = new Set(visible);
  return {
    visible,
    overflow: all.filter((i) => !visibleSet.has(i)),
  };
}

export function StudioNav() {
  const pathname = usePathname();
  const router = useRouter();
  const { mode } = useDesignMode();
  const navRef = useRef<HTMLElement>(null);
  const measureRef = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState<number[]>(() => links.map((_, i) => i));
  const [overflow, setOverflow] = useState<number[]>([]);

  const activeIndex = useMemo(
    () => links.findIndex((link) => matchesPath(pathname, link.href)),
    [pathname],
  );

  useLayoutEffect(() => {
    const nav = navRef.current;
    const measure = measureRef.current;
    if (!nav || !measure) return;

    const update = () => {
      const children = Array.from(measure.children) as HTMLElement[];
      if (children.length < links.length + 1) return;
      const itemWidths = children
        .slice(0, links.length)
        .map((el) => el.getBoundingClientRect().width);
      const moreWidth = children[links.length].getBoundingClientRect().width;
      const styles = getComputedStyle(nav);
      const gap = Number.parseFloat(styles.columnGap || styles.gap) || 0;
      const containerWidth = nav.getBoundingClientRect().width;
      const next = computeVisibleIndices(
        itemWidths,
        moreWidth,
        gap,
        containerWidth,
        activeIndex,
      );
      setVisible(next.visible);
      setOverflow(next.overflow);
    };

    const observer = new ResizeObserver(update);
    observer.observe(nav);
    observer.observe(measure);
    update();
    return () => observer.disconnect();
  }, [activeIndex, mode]);

  const overflowActive = overflow.some((i) => i === activeIndex);

  return (
    <nav
      ref={navRef}
      data-slot="studio-nav"
      className="relative flex min-w-0 flex-1 items-center gap-1 overflow-hidden"
    >
      <div
        ref={measureRef}
        aria-hidden
        className="pointer-events-none absolute flex w-max items-center gap-1 whitespace-nowrap"
        style={{ visibility: "hidden", left: 0, top: 0 }}
      >
        {links.map((link) => {
          const Icon = link.icon;
          return (
            <span key={link.href} className={pillClassName}>
              <Icon data-slot="nav-icon" />
              {link.label}
            </span>
          );
        })}
        <button type="button" tabIndex={-1} className={cn(pillClassName, "appearance-none border-0 bg-transparent")}>
          More
          <ChevronDownIcon className="size-3.5" />
        </button>
      </div>

      {visible.map((index) => {
        const link = links[index];
        const active = index === activeIndex;
        const Icon = link.icon;
        return (
          <Link
            key={link.href}
            href={link.href}
            className={cn(
              pillClassName,
              active
                ? "bg-accent text-accent-foreground"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            <Icon data-slot="nav-icon" />
            {link.label}
          </Link>
        );
      })}

      {overflow.length > 0 && (
        <DropdownMenu>
          <DropdownMenuTrigger
            className={cn(
              pillClassName,
              "cursor-pointer appearance-none border-0 bg-transparent",
              overflowActive
                ? "bg-accent text-accent-foreground"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            More
            <ChevronDownIcon className="size-3.5" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-40 w-auto">
            {overflow.map((index) => {
              const link = links[index];
              const active = index === activeIndex;
              const Icon = link.icon;
              return (
                <DropdownMenuItem
                  key={link.href}
                  className={cn(active && "bg-accent text-accent-foreground")}
                  onClick={() => router.push(link.href)}
                >
                  <Icon data-slot="nav-icon" />
                  {link.label}
                </DropdownMenuItem>
              );
            })}
          </DropdownMenuContent>
        </DropdownMenu>
      )}
    </nav>
  );
}
