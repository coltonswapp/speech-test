/**
 * Studio header destinations. Primary items stay in the bar; secondary tools
 * always live under More (and any primary that cannot fit joins them).
 */

export type StudioNavGroup = "primary" | "more";

export type StudioNavItem = {
  href: string;
  label: string;
  group: StudioNavGroup;
};

/** Content sections that are not the Grammar catalog at `/content`. */
export const CONTENT_SECTIONS = [
  "/content/dialogues",
  "/content/curriculum",
  "/content/patterns",
  "/content/coverage",
] as const;

export const STUDIO_NAV_ITEMS: readonly StudioNavItem[] = [
  { href: "/content/dialogues", label: "Dialogues", group: "primary" },
  { href: "/content/curriculum", label: "Curriculum", group: "primary" },
  { href: "/slides", label: "Slides", group: "primary" },
  { href: "/content", label: "Grammar", group: "primary" },
  { href: "/generate", label: "Generate", group: "primary" },
  { href: "/tts/review", label: "Review queue", group: "primary" },
  { href: "/content/patterns", label: "Patterns", group: "more" },
  { href: "/content/coverage", label: "Coverage", group: "more" },
  { href: "/tts/ambience", label: "Ambience", group: "more" },
  { href: "/tts", label: "TTS Studio", group: "more" },
  { href: "/usage", label: "Usage", group: "more" },
  { href: "/settings", label: "Settings", group: "more" },
] as const;

export const STUDIO_PRIMARY_NAV = STUDIO_NAV_ITEMS.filter(
  (item) => item.group === "primary",
);
export const STUDIO_MORE_NAV = STUDIO_NAV_ITEMS.filter(
  (item) => item.group === "more",
);

export function matchesPath(pathname: string, href: string): boolean {
  if (href === "/content") {
    if (pathname === "/content") return true;
    if (!pathname.startsWith("/content/")) return false;
    return !CONTENT_SECTIONS.some(
      (section) => pathname === section || pathname.startsWith(`${section}/`),
    );
  }
  return pathname === href || pathname.startsWith(`${href}/`);
}

/** Longest matching href so `/tts/ambience` does not highlight TTS Studio. */
export function activeNavIndex(pathname: string): number {
  let best = -1;
  let bestLen = -1;
  STUDIO_NAV_ITEMS.forEach((item, index) => {
    if (!matchesPath(pathname, item.href)) return;
    if (item.href.length > bestLen) {
      best = index;
      bestLen = item.href.length;
    }
  });
  return best;
}

export function activeNavItem(pathname: string): StudioNavItem | null {
  const index = activeNavIndex(pathname);
  return index >= 0 ? STUDIO_NAV_ITEMS[index] : null;
}

/**
 * Which primary pills fit next to an always-visible More control.
 * `activePrimaryIndex` is an index into `itemWidths` (the primary list), or -1.
 */
export function computeVisiblePrimaryIndices(
  itemWidths: number[],
  moreWidth: number,
  gap: number,
  containerWidth: number,
  activePrimaryIndex: number,
): { visible: number[]; overflow: number[] } {
  const n = itemWidths.length;
  const all = Array.from({ length: n }, (_, i) => i);
  const widthOf = (idxs: number[]) => {
    if (idxs.length === 0) return moreWidth;
    return (
      idxs.reduce((sum, i) => sum + itemWidths[i], 0) +
      gap * idxs.length +
      moreWidth
    );
  };
  const canFit = (idxs: number[]) => widthOf(idxs) <= containerWidth + 0.5;

  if (canFit(all)) {
    return { visible: all, overflow: [] };
  }

  const prefix: number[] = [];
  for (let i = 0; i < n; i++) {
    if (canFit([...prefix, i])) prefix.push(i);
    else break;
  }

  let visible = prefix;
  if (activePrimaryIndex >= 0 && !prefix.includes(activePrimaryIndex)) {
    const next = [...prefix];
    while (next.length > 0 && !canFit([...next, activePrimaryIndex])) {
      next.pop();
    }
    if (canFit([...next, activePrimaryIndex])) {
      next.push(activePrimaryIndex);
      visible = next;
    }
  }

  const visibleSet = new Set(visible);
  return {
    visible,
    overflow: all.filter((i) => !visibleSet.has(i)),
  };
}
