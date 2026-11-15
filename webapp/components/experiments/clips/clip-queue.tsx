"use client";

import { useCallback, useMemo, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { ChevronLeftIcon, ExternalLinkIcon, Loader2Icon, TerminalIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { formatApiError } from "@/lib/api-error";
import { clipsApi } from "@/lib/experiments/clips/client";
import { clipQueueClipId, type ClipQueueRow, type ClipQueueStatus } from "@/lib/experiments/clips/queue";
import { ClipUploadPanel, type ClipUploadTicketState } from "@/components/experiments/clips/clip-upload-panel";
import { ClipQueueBatchPanel, type ClipQueueBatch } from "@/components/experiments/clips/clip-queue-batch";
import { usePersistentState } from "@/components/experiments/clips/use-persistent-state";
import { cn } from "@/lib/utils";

// Studio view of the clip queue (lib/experiments/clips/queue.ts): Shorts from
// the competitor index waiting to become clips. "Make clip" saves the clip's
// details and shows the clip audio script command, the same as New clip;
// "Next 5 / 10 / 25" does that for the top of To do in one command.

const BATCH_SIZES = [5, 10, 25] as const;

/**
 * The next `size` rows, one per channel while that lasts, so a batch shows a
 * spread of channels instead of the nine Shorts of the top one.
 */
function pickBatch(rows: ClipQueueRow[], size: number): ClipQueueRow[] {
  const picked: ClipQueueRow[] = [];
  const channels = new Set<string>();
  for (const row of rows) {
    if (picked.length >= size) break;
    const channel = row.channelId ?? row.channelName;
    if (channels.has(channel)) continue;
    channels.add(channel);
    picked.push(row);
  }
  for (const row of rows) {
    if (picked.length >= size) break;
    if (!picked.includes(row)) picked.push(row);
  }
  return picked;
}

type QueueResponse = { rows: ClipQueueRow[]; channels: number; updatedAt: string };

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, init);
  if (!response.ok) {
    throw new Error(formatApiError(await response.json().catch(() => null), response.status));
  }
  return response.json() as Promise<T>;
}

const queueApi = {
  list: () => request<QueueResponse>("/api/experiments/clip-queue"),
  setStatus: (videoIds: string[], status: ClipQueueStatus, note?: string) =>
    request<{ changed: number }>("/api/experiments/clip-queue", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ videoIds, status, ...(note !== undefined ? { note } : {}) }),
    }),
};

type Tab = "todo" | "fetching" | "clipped" | "skipped";

const TABS: { tab: Tab; label: string }[] = [
  { tab: "todo", label: "To do" },
  { tab: "fetching", label: "Waiting for audio" },
  { tab: "clipped", label: "Clipped" },
  { tab: "skipped", label: "Skipped" },
];

function rowTab(row: ClipQueueRow): Tab {
  if (row.progress === "clipped") return "clipped";
  if (row.progress === "fetching") return "fetching";
  return row.status === "skipped" ? "skipped" : "todo";
}

const PAGE = 50;
const QUERY_KEY = ["experiment-clip-queue"];

export function ClipQueue() {
  const query = useQuery({ queryKey: QUERY_KEY, queryFn: queueApi.list });
  const rows = useMemo(() => query.data?.rows ?? [], [query.data]);
  const [tab, setTab] = usePersistentState<Tab>("clip-queue-tab", "todo");
  const [hideWarned, setHideWarned] = usePersistentState("clip-queue-hide-warned", true);
  const [search, setSearch] = useState("");
  const [limit, setLimit] = useState(PAGE);
  const [ticket, setTicket] = useState<ClipUploadTicketState | null>(null);
  const closeTicket = useCallback(() => setTicket(null), []);
  const [batch, setBatch] = useState<ClipQueueBatch | null>(null);
  const queryClient = useQueryClient();

  const counts = useMemo(() => {
    const c: Record<Tab, number> = { todo: 0, fetching: 0, clipped: 0, skipped: 0 };
    for (const row of rows) c[rowTab(row)]++;
    return c;
  }, [rows]);

  const shown = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return rows.filter(
      (row) =>
        rowTab(row) === tab &&
        !(tab === "todo" && hideWarned && row.flags.length > 0) &&
        (!needle ||
          row.title.toLowerCase().includes(needle) ||
          row.channelName.toLowerCase().includes(needle) ||
          row.videoId.toLowerCase() === needle)
    );
  }, [rows, tab, hideWarned, search]);

  // Saves the next Shorts in To do (as filtered) as pending clips, one at a
  // time; a Short whose clip id is taken is left out rather than failing all.
  const startBatch = useMutation({
    mutationFn: async (size: number) => {
      const needle = search.trim().toLowerCase();
      const todo = rows.filter(
        (row) =>
          rowTab(row) === "todo" &&
          !(hideWarned && row.flags.length > 0) &&
          (!needle ||
            row.title.toLowerCase().includes(needle) ||
            row.channelName.toLowerCase().includes(needle))
      );
      const items: ClipQueueBatch["items"] = [];
      const failed: string[] = [];
      for (const row of pickBatch(todo, size)) {
        try {
          const { pending, token } = await clipsApi.createUpload({
            id: clipQueueClipId(row.videoId),
            videoId: row.videoId,
            startSec: 0,
            endSec: null,
            orientation: "portrait",
            splitTargetSec: null,
          });
          items.push({ id: pending.id, videoId: row.videoId, title: row.title, token });
        } catch (error) {
          failed.push(`${row.videoId}: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
      return { items, failed };
    },
    onSuccess: ({ items, failed }) => {
      if (failed.length > 0) toast.error(`Couldn’t add ${failed.length}: ${failed.join(" · ")}`);
      if (items.length === 0) return;
      setTicket(null);
      setBatch({ items });
    },
    onError: (error) => toast.error(error.message),
    onSettled: () => void queryClient.invalidateQueries({ queryKey: QUERY_KEY }),
  });

  return (
    <div className="flex flex-col gap-6">
      <div>
        <Link
          href="/experiments/clips"
          className="mb-1 inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
        >
          <ChevronLeftIcon className="size-3" /> Clip transcripts
        </Link>
        <h1 className="text-xl font-semibold tracking-tight">Clip queue</h1>
        <p className="text-sm text-muted-foreground">
          Shorts waiting to become clips
          {query.data ? `: ${rows.length.toLocaleString()} from ${query.data.channels.toLocaleString()} channels` : ""}.
          Best first: no warnings, then channels the index drew on most. Seed or refresh it with{" "}
          <code>pnpm clip:queue-seed</code>.
        </p>
      </div>

      {ticket ? <ClipUploadPanel key={ticket.token} ticket={ticket} onClose={closeTicket} /> : null}
      {batch ? <ClipQueueBatchPanel batch={batch} onClose={() => setBatch(null)} /> : null}

      {counts.todo > 0 ? (
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-sm font-medium">Make a batch</span>
          {BATCH_SIZES.map((size) => (
            <Button
              key={size}
              type="button"
              size="sm"
              variant="outline"
              disabled={startBatch.isPending || Boolean(batch)}
              onClick={() => startBatch.mutate(size)}
            >
              {startBatch.isPending && startBatch.variables === size ? <Loader2Icon className="animate-spin" /> : null}
              Next {size}
            </Button>
          ))}
          <span className="text-xs text-muted-foreground">
            From the top of To do (with the filters below), one per channel where possible.
            {batch ? " Hide the current batch to start another." : ""}
          </span>
        </div>
      ) : null}

      <div className="flex flex-wrap items-center gap-2">
        {TABS.map(({ tab: t, label }) => (
          <Button
            key={t}
            type="button"
            size="sm"
            variant={tab === t ? "default" : "outline"}
            onClick={() => {
              setTab(t);
              setLimit(PAGE);
            }}
          >
            {label} <span className="tabular-nums opacity-70">{counts[t].toLocaleString()}</span>
          </Button>
        ))}
        <Input
          className="ml-auto h-8 w-56"
          placeholder="Search title or channel"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setLimit(PAGE);
          }}
        />
        {tab === "todo" ? (
          <div className="flex items-center gap-2">
            <Switch id="hide-warned" checked={hideWarned} onCheckedChange={setHideWarned} />
            <Label htmlFor="hide-warned" className="text-xs">
              Hide entries with warnings
            </Label>
          </div>
        ) : null}
      </div>

      {query.isPending ? (
        <Skeleton className="h-32 w-full" />
      ) : query.isError ? (
        <p className="text-sm text-destructive">{query.error.message}</p>
      ) : rows.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          The queue is empty. Run <code>pnpm clip:queue-seed &lt;dump&gt; &lt;cache&gt; --write</code>.
        </p>
      ) : shown.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nothing here.</p>
      ) : (
        <>
          <ul className="divide-y divide-border/60 rounded-xl border border-border/60">
            {shown.slice(0, limit).map((row) => (
              <QueueRow key={row.videoId} row={row} onTicket={setTicket} />
            ))}
          </ul>
          {shown.length > limit ? (
            <Button type="button" variant="outline" size="sm" className="self-start" onClick={() => setLimit(limit + PAGE)}>
              Show more ({(shown.length - limit).toLocaleString()} left)
            </Button>
          ) : null}
        </>
      )}
    </div>
  );
}

function formatDuration(seconds: number | null): string {
  if (seconds === null) return "?";
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60);
  return m > 0 ? `${m}:${String(s).padStart(2, "0")}` : `${s} s`;
}

function QueueRow({ row, onTicket }: { row: ClipQueueRow; onTicket: (ticket: ClipUploadTicketState) => void }) {
  const queryClient = useQueryClient();
  const refresh = () => void queryClient.invalidateQueries({ queryKey: QUERY_KEY });

  const makeClip = useMutation({
    mutationFn: () =>
      clipsApi.createUpload({
        id: clipQueueClipId(row.videoId),
        videoId: row.videoId,
        startSec: 0,
        endSec: null,
        orientation: "portrait",
        splitTargetSec: null,
      }),
    onSuccess: ({ pending, token }) => {
      onTicket({ id: pending.id, token });
      window.scrollTo({ top: 0, behavior: "smooth" });
    },
    onError: (error) => toast.error(error.message),
    onSettled: refresh,
  });
  const setStatus = useMutation({
    mutationFn: (status: ClipQueueStatus) => queueApi.setStatus([row.videoId], status),
    onError: (error) => toast.error(error.message),
    onSettled: refresh,
  });
  const busy = makeClip.isPending || setStatus.isPending;

  return (
    <li className={cn("flex items-center gap-3 px-4 py-3", row.status === "skipped" && "opacity-60")}>
      {/* eslint-disable-next-line @next/next/no-img-element -- YouTube thumbnail, no optimisation needed */}
      <img
        src={`https://i.ytimg.com/vi/${row.videoId}/mqdefault.jpg`}
        alt=""
        loading="lazy"
        className="h-14 w-24 shrink-0 rounded-md bg-muted object-cover"
      />
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <a
          href={`https://www.youtube.com/shorts/${row.videoId}`}
          target="_blank"
          rel="noreferrer"
          className="inline-flex min-w-0 items-center gap-1 text-sm font-medium hover:underline"
        >
          <span className="truncate">{row.title}</span>
          <ExternalLinkIcon className="size-3 shrink-0 text-muted-foreground" />
        </a>
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
          <span>{row.channelName}</span>
          {row.channelDumpCount > 1 ? <span>· {row.channelDumpCount} in index</span> : null}
          <span>· {formatDuration(row.durationSec)}</span>
          {row.flags.map((flag) => (
            <Badge key={flag} variant="outline" className="border-orange-500/50 text-orange-600 dark:text-orange-400">
              {flag}
            </Badge>
          ))}
          {row.note ? <span className="italic">“{row.note}”</span> : null}
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        {row.progress === "clipped" ? (
          row.clipIds.map((id) => (
            <Link key={id} href={`/experiments/clips/${id}`} className={buttonVariants({ size: "sm", variant: "outline" })}>
              {id}
            </Link>
          ))
        ) : row.progress === "fetching" ? (
          <span className="text-xs text-muted-foreground">Waiting for audio (see Clip transcripts)</span>
        ) : row.status === "skipped" ? (
          <Button type="button" size="sm" variant="ghost" disabled={busy} onClick={() => setStatus.mutate("queued")}>
            Back to queue
          </Button>
        ) : (
          <>
            <Button type="button" size="sm" variant="ghost" disabled={busy} onClick={() => setStatus.mutate("skipped")}>
              Skip
            </Button>
            <Button type="button" size="sm" variant="outline" disabled={busy} onClick={() => makeClip.mutate()}>
              {makeClip.isPending ? <Loader2Icon className="animate-spin" /> : <TerminalIcon />}
              Make clip
            </Button>
          </>
        )}
      </div>
    </li>
  );
}
