"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { CheckIcon, CircleAlertIcon, CopyIcon, Loader2Icon, TerminalIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { clipsApi } from "@/lib/experiments/clips/client";
import { FeedBadge, ProcessAllButton } from "@/components/experiments/clips/clip-list";

// A batch from the clip queue: several Shorts saved as pending clips at once,
// one command that fetches all their audio (public/clip-fetch.mjs takes many
// links), then Process all on whatever was made, and a list to review.

export type ClipQueueBatch = {
  items: { id: string; videoId: string; title: string; token: string }[];
};

function batchCommand(batch: ClipQueueBatch): string {
  const origin = window.location.origin;
  const links = batch.items
    .map((item) => `'${origin}/hooks/clip-upload/${item.id}#${item.token}'`)
    .join(" ");
  return `curl -fsSL '${origin}/clip-fetch.mjs' | node --input-type=module - ${links}`;
}

export function ClipQueueBatchPanel({
  batch,
  onClose,
}: {
  batch: ClipQueueBatch;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const [copied, setCopied] = useState(false);
  const command = batchCommand(batch);

  const statuses = useQueries({
    queries: batch.items.map((item) => ({
      queryKey: ["experiment-clip-upload", item.id],
      queryFn: () => clipsApi.uploadStatus(item.id),
      // Stop polling once the clip is made or the pending record is gone.
      refetchInterval: (q: { state: { data?: { created: string[] | null; pending: unknown } } }) => {
        const data = q.state.data;
        return data && (data.created !== null || data.pending === null) ? false : 3000;
      },
    })),
  });
  const created = batch.items.map((_, i) => statuses[i]?.data?.created ?? null);
  const waiting = batch.items.filter((_, i) => {
    const data = statuses[i]?.data;
    return !data || (data.created === null && data.pending !== null);
  });
  const madeIds = created.flatMap((ids) => ids ?? []);
  const allSettled = waiting.length === 0;

  // Refresh the queue (and the clip list) whenever another clip lands.
  const madeCount = madeIds.length;
  useEffect(() => {
    if (madeCount === 0) return;
    void queryClient.invalidateQueries({ queryKey: ["experiment-clip-queue"] });
    void queryClient.invalidateQueries({ queryKey: ["experiment-clips"] });
  }, [madeCount, queryClient]);

  const clipsQuery = useQuery({
    queryKey: ["experiment-clips"],
    queryFn: () => clipsApi.list(),
    enabled: madeIds.length > 0,
  });
  const madeClips = (clipsQuery.data?.clips ?? [])
    .filter((clip) => madeIds.includes(clip.id))
    .sort((a, b) => madeIds.indexOf(a.id) - madeIds.indexOf(b.id));

  // Back to the queue: drop the pending records the script never filled.
  const discardWaiting = useMutation({
    mutationFn: () => Promise.all(waiting.map((item) => clipsApi.cancelUpload(item.id))),
    onSuccess: () => {
      for (const item of waiting) {
        void queryClient.invalidateQueries({ queryKey: ["experiment-clip-upload", item.id] });
      }
      void queryClient.invalidateQueries({ queryKey: ["experiment-clip-queue"] });
    },
    onError: (error) => toast.error(error.message),
  });

  return (
    <section className="flex flex-col gap-3 rounded-xl border border-primary/40 bg-primary/5 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <TerminalIcon className="size-4" />
        <h2 className="text-sm font-medium">Batch of {batch.items.length} Shorts</h2>
        {allSettled ? (
          <Badge variant="secondary">
            {madeIds.length} {madeIds.length === 1 ? "clip" : "clips"} made
          </Badge>
        ) : (
          <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <Loader2Icon className="size-3 animate-spin" /> {batch.items.length - waiting.length} of{" "}
            {batch.items.length} done
          </span>
        )}
      </div>

      {!allSettled ? (
        <>
          <div className="flex items-start gap-2">
            <code className="max-h-32 min-w-0 flex-1 overflow-y-auto rounded-lg border border-border/60 bg-background px-3 py-2 font-mono text-xs break-all select-all">
              {command}
            </code>
            <Button
              type="button"
              variant="outline"
              size="icon"
              aria-label="Copy command"
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(command);
                  setCopied(true);
                  setTimeout(() => setCopied(false), 2000);
                } catch {
                  toast.error("Couldn’t copy. Select the command and copy it instead.");
                }
              }}
            >
              {copied ? <CheckIcon /> : <CopyIcon />}
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            Paste it into Terminal (needs Node and <code>brew install yt-dlp ffmpeg</code>). It fetches
            each Short’s audio in turn; one that fails (deleted, private) doesn’t stop the rest. The
            command works once, for 24 hours.
          </p>
        </>
      ) : null}

      <ul className="flex flex-col gap-1 text-sm">
        {batch.items.map((item, i) => {
          const ids = created[i];
          const data = statuses[i]?.data;
          const gone = data !== undefined && data.created === null && data.pending === null;
          return (
            <li key={item.id} className="flex items-center gap-2">
              {ids ? (
                <CheckIcon className="size-4 shrink-0 text-emerald-600" />
              ) : gone ? (
                <CircleAlertIcon className="size-4 shrink-0 text-muted-foreground" />
              ) : (
                <Loader2Icon className="size-4 shrink-0 animate-spin text-muted-foreground" />
              )}
              <span className="min-w-0 truncate">{item.title}</span>
              {gone ? <span className="text-xs text-muted-foreground">discarded</span> : null}
              {(ids ?? []).map((id) => {
                const clip = madeClips.find((c) => c.id === id);
                return (
                  <span key={id} className="flex shrink-0 items-center gap-1">
                    <Link href={`/experiments/clips/${id}`} className="font-mono text-xs underline underline-offset-2">
                      {id}
                    </Link>
                    {clip?.jlptLevel ? <Badge variant="outline">N{clip.jlptLevel}</Badge> : null}
                    {clip ? <FeedBadge clip={clip} /> : null}
                  </span>
                );
              })}
            </li>
          );
        })}
      </ul>

      <div className="flex flex-wrap items-center gap-2">
        {waiting.length > 0 && waiting.length < batch.items.length ? (
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={discardWaiting.isPending}
            title="For Shorts the script couldn’t fetch: drops their pending clips so they go back to To do"
            onClick={() => discardWaiting.mutate()}
          >
            Discard the {waiting.length} still waiting
          </Button>
        ) : null}
        <Button type="button" variant="ghost" size="sm" onClick={onClose}>
          Hide
        </Button>
        {madeClips.length > 0 ? <ProcessAllButton clips={madeClips} /> : null}
      </div>
    </section>
  );
}
