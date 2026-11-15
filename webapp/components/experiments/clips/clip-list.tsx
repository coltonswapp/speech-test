"use client";

import { useCallback, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  CheckIcon,
  ChevronLeftIcon,
  CopyIcon,
  FileAudioIcon,
  Loader2Icon,
  PlusIcon,
  UploadIcon,
  WandSparklesIcon,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { clipsApi } from "@/lib/experiments/clips/client";
import { cn } from "@/lib/utils";
import { FEED_STATE_LABELS, clipFeedNotReady, clipFeedStatus } from "@/lib/experiments/clips/feed";
import {
  CLIP_ID_PATTERN,
  CLIP_MAX_SECONDS,
  CLIP_SAMPLE_RATE,
  CLIP_SPLIT_DEFAULT_TARGET_SECONDS,
  CLIP_SPLIT_MAX_SECONDS,
  CLIP_SPLIT_MIN_TARGET_SECONDS,
  clipHasUntimedLines,
  clipIsAligned,
  clipIsTokenized,
  clipIsTranslated,
  type ClipSummary,
} from "@/lib/experiments/clips/types";
import { splitAtPauses, splitClipId } from "@/lib/experiments/clips/split";
import {
  decodeFileToMono,
  encodeSamplesToWav,
} from "@/lib/experiments/clips/wav-encode";
import {
  formatTimecode,
  parseTimecode,
  parseYouTubeId,
} from "@/components/experiments/clips/clip-format";
import {
  ClipCatalogControls,
  DEFAULT_CATALOG_VIEW,
  applyCatalogView,
  type CatalogView,
} from "@/components/experiments/clips/clip-catalog";
import {
  ClipUploadPanel,
  PendingClipList,
  type ClipUploadTicketState,
} from "@/components/experiments/clips/clip-upload-panel";
import { usePersistentState } from "@/components/experiments/clips/use-persistent-state";

const CLIP_LIST_PAGE = 50;

export function ClipList() {
  const clipsQuery = useQuery({
    queryKey: ["experiment-clips"],
    queryFn: () => clipsApi.list(),
  });
  const clips = clipsQuery.data?.clips ?? [];
  const pending = clipsQuery.data?.pending ?? [];
  // The script command for a clip whose details were just saved (or reissued).
  const [ticket, setTicket] = useState<ClipUploadTicketState | null>(null);
  const closeTicket = useCallback(() => setTicket(null), []);
  const [storedView, setView] = usePersistentState<Partial<CatalogView>>("clip-catalog-view", {});
  const view: CatalogView = { ...DEFAULT_CATALOG_VIEW, ...storedView };
  const shown = applyCatalogView(clips, view);
  // Render a page at a time: with thousands of Shorts the full list is slow to draw.
  const [limit, setLimit] = useState(CLIP_LIST_PAGE);
  const groups = view.grouped ? groupByVideo(shown) : [];
  const total = view.grouped ? groups.length : shown.length;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <Link
          href="/experiments"
          className="mb-1 inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
        >
          <ChevronLeftIcon className="size-3" /> Experiments
        </Link>
        <h1 className="text-xl font-semibold tracking-tight">Clip transcripts</h1>
        <p className="text-sm text-muted-foreground">
          Cut a window from a YouTube video (or split a whole video into a run of clips),
          transcribe it, tokenize it, and force-align word timestamps. Shorts waiting to be
          clipped are in the{" "}
          <Link href="/experiments/clips/queue" className="underline underline-offset-2">
            clip queue
          </Link>
          .
        </p>
      </div>

      <NewClipForm onTicket={setTicket} />

      {ticket ? <ClipUploadPanel key={ticket.token} ticket={ticket} onClose={closeTicket} /> : null}

      <PendingClipList
        pending={pending.filter((clip) => clip.id !== ticket?.id)}
        onTicket={setTicket}
        onDiscarded={(id) => {
          if (ticket?.id === id) setTicket(null);
        }}
      />

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-medium">Clips</h2>
        {clips.length > 0 ? (
          <ClipCatalogControls clips={clips} shown={shown} view={view} onChange={setView} />
        ) : null}
        {clipsQuery.isPending ? (
          <Skeleton className="h-16 w-full" />
        ) : clipsQuery.isError ? (
          <p className="text-sm text-destructive">{clipsQuery.error.message}</p>
        ) : clips.length === 0 ? (
          <p className="text-sm text-muted-foreground">No clips yet.</p>
        ) : shown.length === 0 ? (
          <p className="text-sm text-muted-foreground">No clips match these filters.</p>
        ) : !view.grouped ? (
          <ul className="divide-y divide-border/60 rounded-xl border border-border/60">
            {shown.slice(0, limit).map((clip) => (
              <ClipRow key={clip.id} clip={clip} />
            ))}
          </ul>
        ) : (
          groups.slice(0, limit).map((group) => (
            <div key={group.videoId} className="rounded-xl border border-border/60">
              {group.clips.length > 1 ? (
                <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-border/60 bg-muted/30 px-4 py-2">
                  <span className="min-w-0 truncate text-sm font-medium">
                    {group.clips.find((clip) => clip.videoTitle)?.videoTitle ?? group.videoId}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {[
                      group.clips.find((clip) => clip.channelName)?.channelName,
                      `${group.clips.length} clips from one video`,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                  <Link
                    href={`/experiments/clips/video/${group.videoId}`}
                    className="text-xs font-medium text-primary hover:underline"
                  >
                    Review all together
                  </Link>
                  <ProcessAllButton clips={group.clips} />
                </div>
              ) : null}
              <ul className="divide-y divide-border/60">
                {group.clips.map((clip) => (
                  <ClipRow key={clip.id} clip={clip} />
                ))}
              </ul>
            </div>
          ))
        )}
        {total > limit ? (
          <Button
            type="button"
            variant="outline"
            size="sm"
            className="self-start"
            onClick={() => setLimit(limit + CLIP_LIST_PAGE)}
          >
            Show more ({(total - limit).toLocaleString()} {view.grouped ? "videos" : "clips"} left)
          </Button>
        ) : null}
      </section>
    </div>
  );
}

/** Clips cut from the same video together (in video order); groups keep the order their first clip has in the list. */
function groupByVideo(clips: ClipSummary[]): { videoId: string; clips: ClipSummary[] }[] {
  const groups = new Map<string, ClipSummary[]>();
  for (const clip of clips) {
    const group = groups.get(clip.videoId);
    if (group) group.push(clip);
    else groups.set(clip.videoId, [clip]);
  }
  return [...groups].map(([videoId, members]) => ({
    videoId,
    clips: [...members].sort((a, b) => a.startSec - b.startSec),
  }));
}

function ClipRow({ clip }: { clip: ClipSummary }) {
  return (
    <li>
      <Link
        href={`/experiments/clips/${clip.id}`}
        className={cn(
          "flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-3 hover:bg-muted/50",
          clip.deprecated && "opacity-60"
        )}
      >
        <span className="font-mono text-sm font-medium">{clip.id}</span>
        <span className="text-xs text-muted-foreground">
          {clip.videoId} · {formatTimecode(clip.startSec)}–{formatTimecode(clip.endSec)} ·{" "}
          {Math.round(clip.endSec - clip.startSec)} s
          {clip.orientation === "portrait" ? " · Short" : ""}
        </span>
        <span className="text-xs text-muted-foreground">{clip.sentenceCount} sentences</span>
        {clip.videoTitle ? (
          <span className="min-w-0 basis-full truncate text-xs text-muted-foreground sm:basis-auto">
            {clip.videoTitle}
            {clip.channelName ? ` · ${clip.channelName}` : ""}
          </span>
        ) : null}
        <span className="ml-auto flex gap-1">
          {clip.deprecated ? <Badge variant="destructive">Deprecated</Badge> : null}
          <Badge variant={clip.jlptLevel ? "secondary" : "outline"}>
            {clip.jlptLevel ? `N${clip.jlptLevel}` : "No level"}
          </Badge>
          <FeedBadge clip={clip} />
          <Badge variant={clip.translated ? "secondary" : "outline"}>English</Badge>
          <Badge variant={clip.highlighted ? "secondary" : "outline"}>Highlights</Badge>
          <Badge variant={clip.tokenized ? "secondary" : "outline"}>Tokenized</Badge>
          <Badge variant={clip.aligned ? "secondary" : "outline"}>Aligned</Badge>
        </span>
      </Link>
    </li>
  );
}

/** In the feed, kept out (hover for why), or not checked yet. Nothing for deprecated clips. */
export function FeedBadge({ clip }: { clip: ClipSummary }) {
  if (clip.deprecated) return null;
  const inFeed = clip.feed === "in" || clip.feed === "manual-in";
  return (
    <Badge
      variant={inFeed ? "secondary" : "outline"}
      className={cn(!inFeed && clip.feed !== "unchecked" && "text-muted-foreground line-through")}
      title={[FEED_STATE_LABELS[clip.feed], clip.feedReason].filter(Boolean).join(": ")}
    >
      Feed
    </Badge>
  );
}

function clipNeedsProcessing(clip: ClipSummary): boolean {
  return (
    !clip.deprecated &&
    (!clip.aligned ||
      !clip.translated ||
      clip.jlptLevel === null ||
      clip.videoTitle === null ||
      clipNeedsFeedCheck(clip))
  );
}

/** Ready for the Feed step and passing the measured rules, but never judged. */
function clipNeedsFeedCheck(clip: ClipSummary): boolean {
  return (
    clip.feed === "unchecked" && clip.aligned && clip.translated && clip.sentenceCount > 0
  );
}

/**
 * Runs every unfinished step on each of a video's clips, one clip at a time:
 * video info, transcribe, tokenize, align, English, level, feed check. Finished steps are skipped and
 * a hand-set level is kept. A clip that fails is reported and the rest carry
 * on; a piece with no speech (music, silence) is left empty.
 */
export function ProcessAllButton({ clips }: { clips: ClipSummary[] }) {
  const queryClient = useQueryClient();
  const pending = clips.filter(clipNeedsProcessing);
  const [progress, setProgress] = useState<string | null>(null);

  const run = useMutation({
    mutationFn: async () => {
      const failed: string[] = [];
      let empty = 0;
      for (const [index, clip] of pending.entries()) {
        const say = (doing: string) =>
          setProgress(`${clip.id}: ${doing} (${index + 1} of ${pending.length})`);
        try {
          say("loading");
          let draft = (await clipsApi.get(clip.id)).draft;
          if (!draft.video) {
            say("getting video info");
            draft = (await clipsApi.videoInfo(clip.id)).draft;
          }
          if (draft.sentences.length === 0) {
            say("transcribing");
            draft = (await clipsApi.step(clip.id, "transcribe")).draft;
          }
          if (draft.sentences.length === 0) {
            empty += 1;
            continue;
          }
          if (!clipIsTokenized(draft)) {
            say("tokenizing");
            draft = (await clipsApi.step(clip.id, "tokenize")).draft;
          }
          if (!clipIsAligned(draft)) {
            say("aligning");
            draft = clipHasUntimedLines(draft)
              ? (await clipsApi.alignUntimed(clip.id)).draft
              : (await clipsApi.step(clip.id, "align")).draft;
          }
          if (!clipIsTranslated(draft)) {
            say("translating");
            draft = (await clipsApi.step(clip.id, "translate")).draft;
          }
          if (!draft.difficulty) {
            say("rating level");
            draft = (await clipsApi.step(clip.id, "level")).draft;
          }
          // Free for clips the measured rules turn down; one model call otherwise.
          if (clipFeedNotReady(draft) === null && clipFeedStatus(draft).state === "unchecked") {
            say("checking for the feed");
            draft = (await clipsApi.step(clip.id, "feed")).draft;
          }
        } catch (error) {
          failed.push(`${clip.id}: ${error instanceof Error ? error.message : String(error)}`);
        }
        void queryClient.invalidateQueries({ queryKey: ["experiment-clips"] });
        // The whole-video page shows each clip's draft; refresh this one.
        void queryClient.invalidateQueries({ queryKey: ["experiment-clip", clip.id] });
      }
      return { failed, empty, done: pending.length - failed.length - empty };
    },
    onSuccess: ({ failed, empty, done }) => {
      const parts = [`Processed ${done} ${done === 1 ? "clip" : "clips"}`];
      if (empty > 0) parts.push(`${empty} had no speech`);
      if (failed.length === 0) {
        toast.success(`${parts.join("; ")}.`);
      } else {
        toast.error(`${parts.join("; ")}; ${failed.length} failed. ${failed.join(" · ")}`, {
          duration: 20_000,
        });
      }
    },
    onError: (error) => toast.error(error.message),
    onSettled: () => {
      setProgress(null);
      void queryClient.invalidateQueries({ queryKey: ["experiment-clips"] });
    },
  });

  if (pending.length === 0) {
    return <span className="ml-auto text-xs text-muted-foreground">All processed</span>;
  }
  return (
    <span className="ml-auto flex items-center gap-2">
      {progress ? <span className="text-xs text-muted-foreground">{progress}</span> : null}
      <Button
        type="button"
        size="sm"
        variant="outline"
        disabled={run.isPending}
        title="Get video info, transcribe, tokenize, align, translate, rate and feed-check every clip that isn’t done yet"
        onClick={() => run.mutate()}
      >
        {run.isPending ? <Loader2Icon className="animate-spin" /> : <WandSparklesIcon />}
        {run.isPending ? "Processing…" : `Process ${pending.length} unfinished`}
      </Button>
    </span>
  );
}

/** Where a new clip's audio comes from. */
type ClipAudioSource = "script" | "file";

function NewClipForm({ onTicket }: { onTicket: (ticket: ClipUploadTicketState) => void }) {
  const router = useRouter();
  // "script": save the details, then one pasted command downloads and uploads.
  // "file": download the audio yourself and pick it.
  const [source, setSource] = usePersistentState<ClipAudioSource>("clip-new-source", "script");
  const viaScript = source === "script";
  const [file, setFile] = useState<File | null>(null);
  const [id, setId] = useState("");
  const [video, setVideo] = useState("");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  // null = follow the download command's start; set once the user types.
  const [fileOffsetOverride, setFileOffsetOverride] = useState<string | null>(null);
  // null = follow the URL (a /shorts/ link is vertical); set once the user flips it.
  const [verticalOverride, setVerticalOverride] = useState<boolean | null>(null);
  const vertical = verticalOverride ?? isShortsUrl(video);
  // null = follow the URL (a Short is usually used whole); set once flipped.
  const [wholeOverride, setWholeOverride] = useState<boolean | null>(null);
  const whole = wholeOverride ?? isShortsUrl(video);
  // Split: cut the range (or whole file) into several clips at pauses.
  const [split, setSplit] = useState(false);
  const [target, setTarget] = useState(String(CLIP_SPLIT_DEFAULT_TARGET_SECONDS));
  const [progress, setProgress] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const startSec = parseTimecode(start);
  const endSec = parseTimecode(end);
  const length = startSec !== null && endSec !== null ? endSec - startSec : null;
  const section = whole ? null : downloadWindow(startSec, endSec);
  const fileOffset = whole ? "0" : (fileOffsetOverride ?? sectionTime(section?.from ?? 0));

  const create = useMutation({
    mutationFn: async () => {
      const videoId = parseYouTubeId(video);
      const startSec = whole ? 0 : parseTimecode(start);
      const endSec = whole ? null : parseTimecode(end);
      const offsetSec = parseTimecode(fileOffset) ?? 0;
      if (!viaScript && !file) throw new Error("Choose an audio or video file.");
      if (!CLIP_ID_PATTERN.test(id)) {
        throw new Error("Clip id: lowercase letters, digits and dashes only.");
      }
      if (!videoId) throw new Error("Enter a YouTube URL or 11-character video id.");
      if (!whole) {
        if (startSec === null || endSec === null) throw new Error("Enter start and end times.");
        if (endSec <= startSec) throw new Error("End must be after start.");
      }
      if (startSec === null) throw new Error("Enter start and end times.");

      const targetSec = split ? Number(target) : CLIP_SPLIT_DEFAULT_TARGET_SECONDS;
      if (
        !Number.isFinite(targetSec) ||
        targetSec < CLIP_SPLIT_MIN_TARGET_SECONDS ||
        targetSec > CLIP_SPLIT_MAX_SECONDS
      ) {
        throw new Error(
          `Clip length must be ${CLIP_SPLIT_MIN_TARGET_SECONDS}–${CLIP_SPLIT_MAX_SECONDS} s.`
        );
      }

      // Script: only the details are saved now; the audio follows from
      // Terminal, and the server cuts it into clips the way the code below does.
      if (viaScript) {
        setProgress("Saving…");
        const { token } = await clipsApi.createUpload({
          id,
          videoId,
          startSec,
          endSec,
          orientation: vertical ? "portrait" : "landscape",
          splitTargetSec: split ? targetSec : null,
        });
        return { created: [], videoId, ticket: { id, token } };
      }
      if (!file) throw new Error("Choose an audio or video file.");

      setProgress("Decoding…");
      const samples = await decodeFileToMono(file);
      const fileSec = samples.length / CLIP_SAMPLE_RATE;
      const from = startSec - offsetSec;
      const to = endSec !== null ? endSec - offsetSec : fileSec;
      if (from < 0) throw new Error("The range starts before the file does; check the file offset.");
      if (from >= fileSec) throw new Error("The range starts after the file ends; check the file offset.");
      if (to > fileSec + 0.5) {
        throw new Error(
          `File is ${fileSec.toFixed(1)} s long; the range ends at ${to.toFixed(1)} s in the file.`
        );
      }
      const range = samples.subarray(
        Math.round(from * CLIP_SAMPLE_RATE),
        Math.min(samples.length, Math.round(to * CLIP_SAMPLE_RATE))
      );
      const rangeSec = Math.floor((range.length / CLIP_SAMPLE_RATE) * 1000) / 1000;
      const round3 = (n: number) => Math.round(n * 1000) / 1000;

      // Fits in one clip and no split asked for: one clip with this id.
      if (!split && rangeSec <= CLIP_MAX_SECONDS) {
        setProgress("Uploading…");
        const { draft } = await clipsApi.create({
          id,
          videoId,
          startSec,
          endSec: endSec ?? round3(startSec + rangeSec),
          orientation: vertical ? "portrait" : "landscape",
          wav: encodeSamplesToWav(range, 0, rangeSec),
        });
        return { created: [draft.id], videoId, ticket: null };
      }

      // Longer than one clip (or split asked for): cut at pauses into a run
      // of clips named <id>-01, <id>-02, …
      const segments = splitAtPauses(range, CLIP_SAMPLE_RATE, targetSec, CLIP_SPLIT_MAX_SECONDS);
      const ids = segments.map((_, i) => splitClipId(id, i, segments.length));
      // Check every id up front so a clash can't leave half a video uploaded.
      const taken = new Set((await clipsApi.list()).clips.map((clip) => clip.id));
      const clash = ids.find((candidate) => taken.has(candidate));
      if (clash) throw new Error(`Clip “${clash}” already exists. Pick another id prefix.`);
      for (const [i, segment] of segments.entries()) {
        setProgress(`Uploading ${i + 1} of ${segments.length}…`);
        try {
          await clipsApi.create({
            id: ids[i],
            videoId,
            startSec: round3(startSec + segment.startSec),
            endSec: round3(startSec + segment.endSec),
            orientation: vertical ? "portrait" : "landscape",
            wav: encodeSamplesToWav(range, segment.startSec, segment.endSec),
          });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          throw new Error(
            i === 0 ? message : `Created ${i} of ${segments.length} clips, then failed: ${message}`
          );
        }
      }
      return { created: ids, videoId, ticket: null };
    },
    onSuccess: ({ created, videoId, ticket }) => {
      if (ticket) {
        toast.success(`Saved ${ticket.id}. Run the command to add the audio.`);
        onTicket(ticket);
        return;
      }
      if (created.length === 1) {
        toast.success(`Created ${created[0]}.`);
        router.push(`/experiments/clips/${created[0]}`);
        return;
      }
      toast.success(
        `Created ${created.length} clips (${created[0]} … ${created[created.length - 1]}). Process them here to transcribe, tokenize and align.`
      );
      router.push(`/experiments/clips/video/${videoId}`);
    },
    onError: (error) => toast.error(error.message),
    onSettled: () => {
      setProgress(null);
      void queryClient.invalidateQueries({ queryKey: ["experiment-clips"] });
    },
  });

  return (
    <form
      className="flex flex-col gap-4 rounded-xl border border-border/60 p-4"
      onSubmit={(event) => {
        event.preventDefault();
        create.mutate();
      }}
    >
      <h2 className="text-sm font-medium">New clip</h2>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="flex flex-wrap items-center gap-2 sm:col-span-2">
          <Label>Audio from</Label>
          <div className="inline-flex gap-0.5 rounded-lg border border-border/60 p-0.5">
            <Button
              type="button"
              size="sm"
              variant={viaScript ? "secondary" : "ghost"}
              aria-pressed={viaScript}
              onClick={() => setSource("script")}
            >
              Terminal script
            </Button>
            <Button
              type="button"
              size="sm"
              variant={viaScript ? "ghost" : "secondary"}
              aria-pressed={!viaScript}
              onClick={() => setSource("file")}
            >
              Choose a file
            </Button>
          </div>
          <span className="text-xs text-muted-foreground">
            {viaScript
              ? "Save the details here; one command then downloads the audio and attaches it"
              : "Download the audio yourself, then pick the file"}
          </span>
        </div>
        <Field
          label={split ? "Clip id prefix" : "Clip id"}
          hint={
            split
              ? `Clips are named ${id || "lions"}-01, ${id || "lions"}-02, … in video order`
              : "Used in the app and R2 key, e.g. lions-01"
          }
        >
          <Input
            value={id}
            onChange={(e) => setId(e.target.value.toLowerCase())}
            placeholder={split ? "lions" : "lions-01"}
          />
        </Field>
        <Field label="YouTube video" hint="URL or video id; must be public or unlisted">
          <Input value={video} onChange={(e) => setVideo(e.target.value)} placeholder="https://youtu.be/…" />
        </Field>
        <div className="flex items-center gap-2 sm:col-span-2">
          <Switch id="new-clip-whole" checked={whole} onCheckedChange={setWholeOverride} />
          <Label htmlFor="new-clip-whole">Whole video</Label>
          <span className="text-xs text-muted-foreground">
            {whole
              ? `Start and end come from the ${viaScript ? "video" : "file"}. Over ${CLIP_MAX_SECONDS} s, it’s split into clips automatically.`
              : "Off: enter start and end times"}
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-2 sm:col-span-2">
          <Switch id="new-clip-split" checked={split} onCheckedChange={setSplit} />
          <Label htmlFor="new-clip-split">Split into clips</Label>
          {split ? (
            <>
              <span className="text-xs text-muted-foreground">about</span>
              <Input
                value={target}
                onChange={(e) => setTarget(e.target.value)}
                inputMode="numeric"
                aria-label="Target clip length in seconds"
                className="h-8 w-16"
              />
              <span className="text-xs text-muted-foreground">
                s each, cut at the nearest pause. Any length of video; every clip keeps this video
                id with its own start and end.
              </span>
            </>
          ) : (
            <span className="text-xs text-muted-foreground">
              Off: one clip, unless it’s over {CLIP_MAX_SECONDS} s, which is split into ~
              {CLIP_SPLIT_DEFAULT_TARGET_SECONDS} s clips automatically
            </span>
          )}
        </div>
        {whole ? null : (
          <>
            <Field label="Start (video time)" hint="m:ss or seconds">
              <Input value={start} onChange={(e) => setStart(e.target.value)} placeholder="5:12" />
            </Field>
            <Field
              label="End (video time)"
              hint={
                length !== null && length > 0
                  ? `${length.toFixed(1)} s${!split && length > CLIP_MAX_SECONDS ? ` (will be split into ~${CLIP_SPLIT_DEFAULT_TARGET_SECONDS} s clips)` : ""}`
                  : `Any length; over ${CLIP_MAX_SECONDS} s is cut into clips`
              }
            >
              <Input value={end} onChange={(e) => setEnd(e.target.value)} placeholder="6:41.5" />
            </Field>
          </>
        )}
        <div className="flex items-center gap-2 sm:col-span-2">
          <Switch id="new-clip-vertical" checked={vertical} onCheckedChange={setVerticalOverride} />
          <Label htmlFor="new-clip-vertical">Vertical Short (9:16)</Label>
          <span className="text-xs text-muted-foreground">
            {verticalOverride === null && vertical
              ? "On because this is a Shorts link"
              : "The app gives vertical clips a taller player"}
          </span>
        </div>
        {viaScript ? null : (
          <>
            <DownloadCommand videoId={parseYouTubeId(video)} section={section} whole={whole} />
            <Field
              label="Audio file"
              hint="Local copy of the video or its audio (MP4, M4A, MP3, WAV)"
            >
              <FileDrop file={file} onFile={setFile} />
            </Field>
          </>
        )}
        {whole || viaScript ? null : <Field
          label="File starts at (video time)"
          hint={
            fileOffsetOverride === null
              ? "Filled in to match the download command above"
              : "0 if the file is the whole video; otherwise where in the video it begins"
          }
        >
          <Input
            value={fileOffset}
            onChange={(e) => setFileOffsetOverride(e.target.value)}
            placeholder="0"
          />
        </Field>}
      </div>
      <div>
        <Button type="submit" disabled={create.isPending}>
          {create.isPending ? <Loader2Icon className="animate-spin" /> : <PlusIcon />}
          {create.isPending
            ? (progress ?? "Cutting and uploading…")
            : viaScript
              ? "Save and get command"
              : split
                ? "Split and create clips"
                : "Create clip"}
        </Button>
      </div>
    </form>
  );
}

function isShortsUrl(value: string): boolean {
  return /\/shorts\//.test(value);
}

/** Seconds of margin downloaded on each side of the clip. */
type DownloadWindow = { from: number; until: number };

/** Seconds as yt-dlp section text: at most 3 decimals, no trailing zeros. */
function sectionTime(seconds: number): string {
  return String(Number(seconds.toFixed(3)));
}

/** Exactly the clip: the downloaded file is the clip, starting at `from`. */
function downloadWindow(startSec: number | null, endSec: number | null): DownloadWindow | null {
  if (startSec === null || endSec === null || endSec <= startSec) return null;
  return { from: startSec, until: endSec };
}

/**
 * Ready-to-run yt-dlp command for this clip. A section that starts after 0:00
 * uses --force-keyframes-at-cuts so the file begins exactly at `from` (file
 * time + from = video time, which "File starts at" is pre-filled with). Runs
 * on your own machine; Studio never downloads from YouTube.
 */
function DownloadCommand({
  videoId,
  section,
  whole,
}: {
  videoId: string | null;
  section: DownloadWindow | null;
  /** Download the whole video; `section` is ignored. */
  whole: boolean;
}) {
  const [copied, setCopied] = useState(false);
  const ready = videoId !== null && (whole || section !== null);
  const command = ready
    ? [
        "yt-dlp -f bestaudio -x --audio-format m4a",
        !whole && section
          ? `--download-sections "*${sectionTime(section.from)}-${sectionTime(section.until)}"`
          : null,
        !whole && section && section.from > 0 ? "--force-keyframes-at-cuts" : null,
        `-o "~/Downloads/%(id)s.%(ext)s" "https://www.youtube.com/watch?v=${videoId}"`,
      ]
        .filter(Boolean)
        .join(" ")
    : "";

  return (
    <div className="flex flex-col gap-1.5 sm:col-span-2">
      <Label>Get the audio</Label>
      {ready ? (
        <>
          <div className="flex items-start gap-2 rounded-lg border border-border/60 bg-muted/40 p-2">
            <code className="min-w-0 flex-1 break-all font-mono text-xs leading-relaxed">{command}</code>
            <Button
              type="button"
              variant="ghost"
              size="icon-sm"
              aria-label="Copy command"
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(command);
                  setCopied(true);
                  setTimeout(() => setCopied(false), 1500);
                } catch {
                  toast.error("Couldn’t copy. Select the command and copy it instead.");
                }
              }}
            >
              {copied ? <CheckIcon /> : <CopyIcon />}
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            Run in Terminal (needs <code>brew install yt-dlp ffmpeg</code>). It saves{" "}
            <code>~/Downloads/{videoId}.m4a</code>
            {whole || !section ? (
              <>, the whole video. Choose that file.</>
            ) : (
              <>
                , starting at {formatTimecode(section.from)} in the video. “File starts at” below is
                filled in to match; choose that file.
              </>
            )}
          </p>
        </>
      ) : (
        <p className="text-xs text-muted-foreground">
          {whole
            ? "Enter the YouTube video to get a download command."
            : "Enter the YouTube video and start and end times to get a download command."}
        </p>
      )}
    </div>
  );
}

function formatBytes(bytes: number): string {
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/** Click or drop an audio/video file; shows the chosen file's name and size. */
function FileDrop({ file, onFile }: { file: File | null; onFile: (file: File | null) => void }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = useState(false);

  const accept = (candidate: File | undefined) => {
    if (!candidate) return;
    if (!/^(audio|video)\//.test(candidate.type) && !/\.(m4a|mp3|mp4|wav|webm|ogg|opus|aac|mov)$/i.test(candidate.name)) {
      toast.error(`“${candidate.name}” isn’t an audio or video file.`);
      return;
    }
    onFile(candidate);
  };

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => inputRef.current?.click()}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          inputRef.current?.click();
        }
      }}
      onDragOver={(event) => {
        event.preventDefault();
        setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={(event) => {
        event.preventDefault();
        setDragging(false);
        accept(event.dataTransfer.files?.[0]);
      }}
      className={cn(
        "flex min-h-14 cursor-pointer items-center gap-3 rounded-lg border border-dashed px-3 py-2 text-sm outline-none transition-colors focus-visible:ring-3 focus-visible:ring-ring/50",
        dragging
          ? "border-primary bg-primary/5"
          : file
            ? "border-border bg-muted/30"
            : "border-input hover:bg-muted/40"
      )}
    >
      <input
        ref={inputRef}
        type="file"
        accept="audio/*,video/*"
        className="hidden"
        onChange={(event) => {
          accept(event.target.files?.[0]);
          event.target.value = ""; // lets the same file be chosen again
        }}
      />
      {file ? (
        <>
          <FileAudioIcon className="size-4 shrink-0 text-muted-foreground" />
          <span className="min-w-0 flex-1">
            <span className="block truncate font-medium">{file.name}</span>
            <span className="text-xs text-muted-foreground">{formatBytes(file.size)}</span>
          </span>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={(event) => {
              event.stopPropagation();
              onFile(null);
            }}
          >
            Remove
          </Button>
        </>
      ) : (
        <>
          <UploadIcon className="size-4 shrink-0 text-muted-foreground" />
          <span className="text-muted-foreground">
            {dragging ? "Drop to use this file" : "Drop a file here, or click to choose"}
          </span>
        </>
      )}
    </div>
  );
}

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <Label>{label}</Label>
      {children}
      {hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}
    </div>
  );
}
