"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { CheckIcon, CopyIcon, Loader2Icon, TerminalIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { clipsApi } from "@/lib/experiments/clips/client";
import type { ClipPendingInfo } from "@/lib/experiments/clips/types";
import { formatTimecode } from "@/components/experiments/clips/clip-format";

// Script-made clips: Studio saves the details, public/clip-fetch.mjs (run on
// your own machine) downloads the audio with yt-dlp and uploads it. The token is
// shown once, in the command; Studio only keeps its hash.

/** A pending clip and the one-time token for its command. */
export type ClipUploadTicketState = { id: string; token: string };

function fetchCommand(ticket: ClipUploadTicketState): string {
  // Fetches the script from this Studio and pipes it into node, so it runs
  // from any folder and always matches the deployed server.
  const origin = window.location.origin;
  return `curl -fsSL '${origin}/clip-fetch.mjs' | node --input-type=module - '${origin}/hooks/clip-upload/${ticket.id}#${ticket.token}'`;
}

/** The command to run, and a wait for the script to finish; then opens the new clip. */
export function ClipUploadPanel({
  ticket,
  onClose,
}: {
  ticket: ClipUploadTicketState;
  /** The clip was created or discarded, or the panel was dismissed. */
  onClose: () => void;
}) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [copied, setCopied] = useState(false);
  const command = fetchCommand(ticket);

  const status = useQuery({
    queryKey: ["experiment-clip-upload", ticket.id],
    queryFn: () => clipsApi.uploadStatus(ticket.id),
    refetchInterval: 2500,
  });
  const created = status.data?.created ?? null;
  const createdVideoId = status.data?.videoId ?? null;
  const gone = status.data !== undefined && created === null && status.data.pending === null;

  useEffect(() => {
    if (!created || created.length === 0) return;
    // The record only existed to tell this page what was made.
    void clipsApi.cancelUpload(ticket.id).catch(() => undefined);
    void queryClient.invalidateQueries({ queryKey: ["experiment-clips"] });
    onClose();
    if (created.length === 1 || !createdVideoId) {
      toast.success(`Created ${created[0]}.`);
      router.push(`/experiments/clips/${created[0]}`);
      return;
    }
    toast.success(
      `Created ${created.length} clips (${created[0]} … ${created[created.length - 1]}). Process them here to transcribe, tokenize and align.`
    );
    router.push(`/experiments/clips/video/${createdVideoId}`);
  }, [created, createdVideoId, ticket.id, queryClient, router, onClose]);

  const discard = useMutation({
    mutationFn: () => clipsApi.cancelUpload(ticket.id),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["experiment-clips"] });
      onClose();
    },
    onError: (error) => toast.error(error.message),
  });

  return (
    <section className="flex flex-col gap-3 rounded-xl border border-primary/40 bg-primary/5 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <TerminalIcon className="size-4" />
        <h2 className="text-sm font-medium">
          Add the audio for <span className="font-mono">{ticket.id}</span>
        </h2>
        {gone ? (
          <Badge variant="destructive">Discarded</Badge>
        ) : (
          <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <Loader2Icon className="size-3 animate-spin" /> Waiting for the script
          </span>
        )}
      </div>
      <div className="flex items-start gap-2">
        <code className="min-w-0 flex-1 rounded-lg border border-border/60 bg-background px-3 py-2 font-mono text-xs break-all select-all">
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
        Paste it into Terminal, in any folder (needs Node and{" "}
        <code>brew install yt-dlp ffmpeg</code>). It downloads the audio from YouTube and uploads
        it; audio too long for one clip is split into clips at pauses. This page opens the result
        when it’s done. The command works once, for 24 hours; treat it like a password until then.
      </p>
      <div className="flex gap-2">
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={discard.isPending}
          onClick={() => discard.mutate()}
        >
          Discard clip
        </Button>
        <Button type="button" variant="ghost" size="sm" onClick={onClose}>
          Hide
        </Button>
      </div>
    </section>
  );
}

/** Clips whose details are saved but whose audio hasn't been uploaded yet. */
export function PendingClipList({
  pending,
  onTicket,
  onDiscarded,
}: {
  pending: ClipPendingInfo[];
  onTicket: (ticket: ClipUploadTicketState) => void;
  onDiscarded: (id: string) => void;
}) {
  if (pending.length === 0) return null;
  return (
    <section className="flex flex-col gap-2">
      <h2 className="text-sm font-medium">Waiting for audio</h2>
      <ul className="divide-y divide-border/60 rounded-xl border border-border/60">
        {pending.map((clip) => (
          <PendingClipRow key={clip.id} clip={clip} onTicket={onTicket} onDiscarded={onDiscarded} />
        ))}
      </ul>
    </section>
  );
}

function PendingClipRow({
  clip,
  onTicket,
  onDiscarded,
}: {
  clip: ClipPendingInfo;
  onTicket: (ticket: ClipUploadTicketState) => void;
  onDiscarded: (id: string) => void;
}) {
  const queryClient = useQueryClient();
  const refresh = () => void queryClient.invalidateQueries({ queryKey: ["experiment-clips"] });

  // A fresh token for the same details; the command issued before stops working.
  const reissue = useMutation({
    mutationFn: () =>
      clipsApi.createUpload({
        id: clip.id,
        videoId: clip.videoId,
        startSec: clip.startSec,
        endSec: clip.endSec,
        orientation: clip.orientation,
        splitTargetSec: clip.splitTargetSec,
      }),
    onSuccess: ({ token }) => onTicket({ id: clip.id, token }),
    onError: (error) => toast.error(error.message),
    onSettled: refresh,
  });
  const discard = useMutation({
    mutationFn: () => clipsApi.cancelUpload(clip.id),
    onSuccess: () => onDiscarded(clip.id),
    onError: (error) => toast.error(error.message),
    onSettled: refresh,
  });
  const busy = reissue.isPending || discard.isPending;

  return (
    <li className="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-3">
      <span className="font-mono text-sm font-medium">{clip.id}</span>
      <span className="text-xs text-muted-foreground">
        {clip.videoId} ·{" "}
        {clip.endSec === null
          ? "whole video"
          : `${formatTimecode(clip.startSec)}–${formatTimecode(clip.endSec)}`}
        {clip.orientation === "portrait" ? " · Short" : ""}
        {clip.splitTargetSec !== null ? ` · split into ~${clip.splitTargetSec} s clips` : ""}
      </span>
      <span className="ml-auto flex items-center gap-2">
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={busy}
          title="Makes a new command; one copied earlier stops working"
          onClick={() => reissue.mutate()}
        >
          {reissue.isPending ? <Loader2Icon className="animate-spin" /> : <TerminalIcon />}
          New command
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          disabled={busy}
          onClick={() => discard.mutate()}
        >
          Discard
        </Button>
      </span>
    </li>
  );
}
