"use client";

import { useLayoutEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  AudioLinesIcon,
  ChartNoAxesColumnIcon,
  ListChecksIcon,
  BookOpenIcon,
  ChevronDownIcon,
  GraduationCapIcon,
  ImagesIcon,
  LayersIcon,
  MessagesSquareIcon,
  PieChartIcon,
  SettingsIcon,
  SparklesIcon,
  WindIcon,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useDesignMode } from "@/components/design-mode-provider";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  STUDIO_MORE_NAV,
  STUDIO_PRIMARY_NAV,
  activeNavItem,
  computeVisiblePrimaryIndices,
  type StudioNavItem,
} from "@/lib/studio-nav";

const ICONS: Record<string, LucideIcon> = {
  "/content/dialogues": MessagesSquareIcon,
  "/content/curriculum": GraduationCapIcon,
  "/slides": ImagesIcon,
  "/content": BookOpenIcon,
  "/generate": SparklesIcon,
  "/tts/review": ListChecksIcon,
  "/content/patterns": LayersIcon,
  "/content/coverage": PieChartIcon,
  "/tts": AudioLinesIcon,
  "/tts/ambience": WindIcon,
  "/usage": ChartNoAxesColumnIcon,
  "/settings": SettingsIcon,
};

const pillClassName =
  "flex shrink-0 items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium whitespace-nowrap transition-colors";

function NavIcon({ href, className }: { href: string; className?: string }) {
  const Icon = ICONS[href];
  if (!Icon) return null;
  return <Icon data-slot="nav-icon" className={className} />;
}

function itemIsActive(item: StudioNavItem, active: StudioNavItem | null) {
  return active?.href === item.href;
}

export function StudioNav() {
  const pathname = usePathname();
  const router = useRouter();
  const { mode } = useDesignMode();
  const navRef = useRef<HTMLElement>(null);
  const measureRef = useRef<HTMLDivElement>(null);
  const [visiblePrimary, setVisiblePrimary] = useState<number[]>(() =>
    STUDIO_PRIMARY_NAV.map((_, i) => i),
  );
  const [overflowPrimary, setOverflowPrimary] = useState<number[]>([]);

  const active = useMemo(() => activeNavItem(pathname), [pathname]);
  const activePrimaryIndex = useMemo(
    () => STUDIO_PRIMARY_NAV.findIndex((item) => itemIsActive(item, active)),
    [active],
  );

  useLayoutEffect(() => {
    const nav = navRef.current;
    const measure = measureRef.current;
    if (!nav || !measure) return;

    const update = () => {
      const children = Array.from(measure.children) as HTMLElement[];
      if (children.length < STUDIO_PRIMARY_NAV.length + 1) return;
      const containerWidth = nav.getBoundingClientRect().width;
      if (containerWidth <= 0) return;
      const itemWidths = children
        .slice(0, STUDIO_PRIMARY_NAV.length)
        .map((el) => el.getBoundingClientRect().width);
      const moreWidth = children[STUDIO_PRIMARY_NAV.length].getBoundingClientRect()
        .width;
      const styles = getComputedStyle(nav);
      const gap = Number.parseFloat(styles.columnGap || styles.gap) || 0;
      const next = computeVisiblePrimaryIndices(
        itemWidths,
        moreWidth,
        gap,
        containerWidth,
        activePrimaryIndex,
      );
      setVisiblePrimary(next.visible);
      setOverflowPrimary(next.overflow);
    };

    const observer = new ResizeObserver(update);
    observer.observe(nav);
    observer.observe(measure);
    update();
    return () => observer.disconnect();
  }, [activePrimaryIndex, mode]);

  const overflowPrimaryItems = overflowPrimary.map((i) => STUDIO_PRIMARY_NAV[i]);
  const moreItems = [...overflowPrimaryItems, ...STUDIO_MORE_NAV];
  const moreContainsActive = moreItems.some((item) => itemIsActive(item, active));
  const ActiveIcon = active ? ICONS[active.href] : undefined;

  return (
    <>
      <div className="flex min-w-0 flex-1 items-center md:hidden">
        <DropdownMenu>
          <DropdownMenuTrigger
            aria-label="Navigate to section"
            className={cn(
              pillClassName,
              "min-h-10 min-w-0 max-w-full cursor-pointer appearance-none border border-border/60 bg-transparent touch-manipulation",
              "text-foreground",
            )}
          >
            {ActiveIcon ? (
              <ActiveIcon className="size-4 shrink-0 text-muted-foreground" />
            ) : null}
            <span className="truncate">{active?.label ?? "Sections"}</span>
            <ChevronDownIcon className="size-3.5 shrink-0 text-muted-foreground" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="min-w-56 w-auto">
            <DropdownMenuGroup>
              <DropdownMenuLabel>Workspace</DropdownMenuLabel>
              {STUDIO_PRIMARY_NAV.map((item) => (
                <NavMenuItem
                  key={item.href}
                  item={item}
                  active={itemIsActive(item, active)}
                  onSelect={() => router.push(item.href)}
                  className="min-h-10 touch-manipulation"
                />
              ))}
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              <DropdownMenuLabel>More</DropdownMenuLabel>
              {STUDIO_MORE_NAV.map((item) => (
                <NavMenuItem
                  key={item.href}
                  item={item}
                  active={itemIsActive(item, active)}
                  onSelect={() => router.push(item.href)}
                  className="min-h-10 touch-manipulation"
                />
              ))}
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <nav
        ref={navRef}
        data-slot="studio-nav"
        className="relative hidden min-w-0 flex-1 items-center gap-1 overflow-hidden md:flex"
      >
        <div
          ref={measureRef}
          aria-hidden
          className="pointer-events-none absolute flex w-max items-center gap-1 whitespace-nowrap"
          style={{ visibility: "hidden", left: 0, top: 0 }}
        >
          {STUDIO_PRIMARY_NAV.map((item) => (
            <span key={item.href} className={pillClassName}>
              <NavIcon href={item.href} />
              {item.label}
            </span>
          ))}
          <button
            type="button"
            tabIndex={-1}
            className={cn(pillClassName, "appearance-none border-0 bg-transparent")}
          >
            More
            <ChevronDownIcon className="size-3.5" />
          </button>
        </div>

        {visiblePrimary.map((index) => {
          const item = STUDIO_PRIMARY_NAV[index];
          const isActive = itemIsActive(item, active);
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={isActive ? "page" : undefined}
              className={cn(
                pillClassName,
                isActive
                  ? "bg-accent text-accent-foreground"
                  : "text-muted-foreground hover:text-foreground",
              )}
            >
              <NavIcon href={item.href} />
              {item.label}
            </Link>
          );
        })}

        <DropdownMenu>
          <DropdownMenuTrigger
            aria-label="More tools"
            aria-haspopup="menu"
            data-active={moreContainsActive ? "true" : undefined}
            className={cn(
              pillClassName,
              "cursor-pointer appearance-none border-0 bg-transparent",
              moreContainsActive
                ? "bg-accent text-accent-foreground"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            More
            <ChevronDownIcon className="size-3.5" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-48 w-auto">
            {overflowPrimaryItems.length > 0 ? (
              <>
                <DropdownMenuGroup>
                  <DropdownMenuLabel>Workspace</DropdownMenuLabel>
                  {overflowPrimaryItems.map((item) => (
                    <NavMenuItem
                      key={item.href}
                      item={item}
                      active={itemIsActive(item, active)}
                      onSelect={() => router.push(item.href)}
                    />
                  ))}
                </DropdownMenuGroup>
                <DropdownMenuSeparator />
              </>
            ) : null}
            <DropdownMenuGroup>
              {overflowPrimaryItems.length > 0 ? (
                <DropdownMenuLabel>More</DropdownMenuLabel>
              ) : null}
              {STUDIO_MORE_NAV.map((item) => (
                <NavMenuItem
                  key={item.href}
                  item={item}
                  active={itemIsActive(item, active)}
                  onSelect={() => router.push(item.href)}
                />
              ))}
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
      </nav>
    </>
  );
}

function NavMenuItem({
  item,
  active,
  onSelect,
  className,
}: {
  item: StudioNavItem;
  active: boolean;
  onSelect: () => void;
  className?: string;
}) {
  return (
    <DropdownMenuItem
      className={cn(active && "bg-accent text-accent-foreground", className)}
      aria-current={active ? "page" : undefined}
      onClick={onSelect}
    >
      <NavIcon href={item.href} className="size-4 text-muted-foreground" />
      {item.label}
    </DropdownMenuItem>
  );
}
