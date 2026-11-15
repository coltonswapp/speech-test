"use client";

import { SearchIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { CLIP_JLPT_LEVELS, type ClipSummary } from "@/lib/experiments/clips/types";

// Browsing the clip catalog: search, filters and sort over the summaries the
// list already loads. All in the browser; the view is remembered per browser.

export type CatalogSort =
  | "updated"
  | "created"
  | "channel"
  | "title"
  | "shortest"
  | "longest"
  | "easiest"
  | "hardest";

export type CatalogStatus =
  | "all"
  | "ready"
  | "feed"
  | "not-feed"
  | "feed-unchecked"
  | "unfinished"
  | "deprecated";

export type CatalogView = {
  search: string;
  /** A channel key (see clipChannelKey), or "all". */
  channel: string;
  /** "all", "none" (not rated) or "1"…"5". */
  level: string;
  status: CatalogStatus;
  sort: CatalogSort;
  /** Keep clips from one video together under a heading. */
  grouped: boolean;
};

export const DEFAULT_CATALOG_VIEW: CatalogView = {
  search: "",
  channel: "all",
  level: "all",
  status: "all",
  sort: "updated",
  grouped: true,
};

const SORT_ITEMS: { value: CatalogSort; label: string }[] = [
  { value: "updated", label: "Recently edited" },
  { value: "created", label: "Newest" },
  { value: "channel", label: "Channel" },
  { value: "title", label: "Video title" },
  { value: "shortest", label: "Shortest first" },
  { value: "longest", label: "Longest first" },
  { value: "easiest", label: "Easiest first" },
  { value: "hardest", label: "Hardest first" },
];

const STATUS_ITEMS: { value: CatalogStatus; label: string }[] = [
  { value: "all", label: "Any status" },
  { value: "ready", label: "In the app" },
  { value: "feed", label: "In the feed" },
  { value: "not-feed", label: "Kept out of the feed" },
  { value: "feed-unchecked", label: "Feed not checked" },
  { value: "unfinished", label: "Unfinished" },
  { value: "deprecated", label: "Deprecated" },
];

const LEVEL_ITEMS = [
  { value: "all", label: "Any level" },
  ...CLIP_JLPT_LEVELS.map((level) => ({ value: String(level), label: `N${level}` })),
  { value: "none", label: "Not rated" },
];

const NO_CHANNEL = "unknown";

/** The channel's page when known (names can change or collide), else its name. */
export function clipChannelKey(clip: ClipSummary): string {
  return clip.channelUrl ?? clip.channelName ?? NO_CHANNEL;
}

export function clipSeconds(clip: ClipSummary): number {
  return Math.max(0, clip.endSec - clip.startSec);
}

/** Aligned and not deprecated: what /api/public/clips lists. */
function clipIsInApp(clip: ClipSummary): boolean {
  return clip.aligned && !clip.deprecated;
}

/** Channels that have clips, by name, each with its clip count. */
export function catalogChannels(
  clips: ClipSummary[]
): { value: string; label: string; count: number }[] {
  const channels = new Map<string, { label: string; count: number }>();
  for (const clip of clips) {
    const key = clipChannelKey(clip);
    const entry = channels.get(key);
    if (entry) entry.count += 1;
    else channels.set(key, { label: clip.channelName ?? "Unknown channel", count: 1 });
  }
  return [...channels]
    .map(([value, { label, count }]) => ({ value, label, count }))
    .sort((a, b) => a.label.localeCompare(b.label));
}

const text = (value: string | null) => (value ?? "").toLocaleLowerCase();

/** Unknown values sort last, whichever way the list runs. */
function byText(a: string | null, b: string | null): number {
  if (a === null || b === null) return a === b ? 0 : a === null ? 1 : -1;
  return a.localeCompare(b);
}

function compareClips(sort: CatalogSort): (a: ClipSummary, b: ClipSummary) => number {
  const inVideoOrder = (a: ClipSummary, b: ClipSummary) =>
    a.videoId.localeCompare(b.videoId) || a.startSec - b.startSec;
  const level = (clip: ClipSummary, unrated: number) => clip.jlptLevel ?? unrated;
  switch (sort) {
    case "updated":
      return (a, b) => b.updatedAt.localeCompare(a.updatedAt);
    case "created":
      return (a, b) => b.createdAt.localeCompare(a.createdAt);
    case "channel":
      return (a, b) =>
        byText(a.channelName, b.channelName) ||
        byText(a.videoTitle, b.videoTitle) ||
        inVideoOrder(a, b);
    case "title":
      return (a, b) => byText(a.videoTitle, b.videoTitle) || inVideoOrder(a, b);
    case "shortest":
      return (a, b) => clipSeconds(a) - clipSeconds(b) || inVideoOrder(a, b);
    case "longest":
      return (a, b) => clipSeconds(b) - clipSeconds(a) || inVideoOrder(a, b);
    case "easiest":
      // 5 = N5 (easiest) … 1 = N1.
      return (a, b) => level(b, 0) - level(a, 0) || inVideoOrder(a, b);
    case "hardest":
      return (a, b) => level(a, 6) - level(b, 6) || inVideoOrder(a, b);
  }
}

/** The clips the view shows, in its order. */
export function applyCatalogView(clips: ClipSummary[], view: CatalogView): ClipSummary[] {
  const words = view.search.toLocaleLowerCase().split(/\s+/).filter(Boolean);
  const shown = clips.filter((clip) => {
    if (view.channel !== "all" && clipChannelKey(clip) !== view.channel) return false;
    if (view.level === "none" && clip.jlptLevel !== null) return false;
    if (view.level !== "all" && view.level !== "none" && String(clip.jlptLevel) !== view.level) {
      return false;
    }
    if (view.status === "ready" && !clipIsInApp(clip)) return false;
    if (view.status === "deprecated" && !clip.deprecated) return false;
    const inFeed = clip.feed === "in" || clip.feed === "manual-in";
    if (view.status === "feed" && !(inFeed && clipIsInApp(clip))) return false;
    if (
      view.status === "not-feed" &&
      (clip.deprecated || (clip.feed !== "out" && clip.feed !== "manual-out"))
    ) {
      return false;
    }
    if (view.status === "feed-unchecked" && (clip.deprecated || clip.feed !== "unchecked")) {
      return false;
    }
    if (
      view.status === "unfinished" &&
      (clip.deprecated || (clip.aligned && clip.translated && clip.jlptLevel !== null))
    ) {
      return false;
    }
    if (words.length > 0) {
      const haystack = [clip.id, text(clip.videoId), text(clip.videoTitle), text(clip.channelName)].join(
        " "
      );
      if (!words.every((word) => haystack.includes(word))) return false;
    }
    return true;
  });
  return shown.sort(compareClips(view.sort));
}

function formatTotal(seconds: number): string {
  const total = Math.round(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
    : `${m}:${String(s).padStart(2, "0")}`;
}

export function ClipCatalogControls({
  clips,
  shown,
  view,
  onChange,
}: {
  /** Every clip (for the channel list and totals). */
  clips: ClipSummary[];
  /** The clips the view lets through. */
  shown: ClipSummary[];
  view: CatalogView;
  onChange: (view: CatalogView) => void;
}) {
  const channels = catalogChannels(clips);
  const channelItems = [
    { value: "all", label: "Any channel" },
    ...channels.map((channel) => ({
      value: channel.value,
      label: `${channel.label} (${channel.count})`,
    })),
  ];
  const filtered =
    view.search !== "" || view.channel !== "all" || view.level !== "all" || view.status !== "all";
  const seconds = shown.reduce((sum, clip) => sum + clipSeconds(clip), 0);

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <SearchIcon className="pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={view.search}
            onChange={(event) => onChange({ ...view, search: event.target.value })}
            placeholder="Search id, title, channel"
            aria-label="Search clips"
            className="h-8 w-56 pl-8"
          />
        </div>
        <CatalogSelect
          label="Channel"
          items={channelItems}
          value={view.channel}
          onChange={(channel) => onChange({ ...view, channel })}
          className="max-w-56"
        />
        <CatalogSelect
          label="Level"
          items={LEVEL_ITEMS}
          value={view.level}
          onChange={(level) => onChange({ ...view, level })}
        />
        <CatalogSelect
          label="Status"
          items={STATUS_ITEMS}
          value={view.status}
          onChange={(status) => onChange({ ...view, status: status as CatalogStatus })}
        />
        <CatalogSelect
          label="Sort"
          items={SORT_ITEMS}
          value={view.sort}
          onChange={(sort) => onChange({ ...view, sort: sort as CatalogSort })}
        />
        <span className="flex items-center gap-2">
          <Switch
            id="clip-catalog-grouped"
            checked={view.grouped}
            onCheckedChange={(grouped) => onChange({ ...view, grouped })}
          />
          <Label htmlFor="clip-catalog-grouped">Group by video</Label>
        </span>
      </div>
      <p className="flex flex-wrap items-center gap-x-2 text-xs text-muted-foreground">
        <span>
          {filtered ? `${shown.length} of ${clips.length} clips` : `${clips.length} clips`} ·{" "}
          {formatTotal(seconds)} of audio
        </span>
        {filtered ? (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-6 px-2 text-xs"
            onClick={() =>
              onChange({ ...DEFAULT_CATALOG_VIEW, sort: view.sort, grouped: view.grouped })
            }
          >
            Clear filters
          </Button>
        ) : null}
      </p>
    </div>
  );
}

function CatalogSelect({
  label,
  items,
  value,
  onChange,
  className,
}: {
  label: string;
  items: { value: string; label: string }[];
  value: string;
  onChange: (value: string) => void;
  className?: string;
}) {
  return (
    <Select
      items={items}
      value={value}
      onValueChange={(next) => {
        if (typeof next === "string" && next) onChange(next);
      }}
    >
      <SelectTrigger aria-label={label} className={className}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {items.map((item) => (
          <SelectItem key={item.value} value={item.value}>
            {item.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
