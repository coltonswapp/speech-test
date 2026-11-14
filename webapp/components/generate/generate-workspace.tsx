"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Download,
  Loader2,
  Pencil,
  RefreshCw,
  Save,
  Sparkles,
  Trash2,
  Upload,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { GenerateLines, newDraftLine, type DraftLine } from "./generate-lines";
import { generateApi, type Generation } from "@/lib/generate/client";
import {
  GENERATE_ALIGNMENT_NOTE,
  GENERATE_TEMPORARY_LIFETIME,
} from "@/lib/generate/types";
import { retainStableRequestId } from "@/lib/generate/request-id";
import { geminiVoiceLabel } from "@/lib/tts/gemini-voice-catalog";
import { ttsApi } from "@/lib/tts/client";
import { GEMINI_TTS_MODELS } from "@/lib/gemini/models";
import { cn } from "@/lib/utils";

const QUERY_KEY = ["generate-clips"];

function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds)) return "—";
  const whole = Math.max(0, seconds);
  const m = Math.floor(whole / 60);
  const s = (whole - m * 60).toFixed(1);
  return m > 0 ? `${m}:${s.padStart(4, "0")}` : `${s}s`;
}

function formatWhen(iso: string): string {
  const date = new Date(iso);
  if (!Number.isFinite(date.getTime())) return iso;
  return date.toLocaleString();
}

function draftsFromGeneration(generation: Generation): DraftLine[] {
  return generation.lines.map((line) => ({
    id: line.id,
    text: line.text,
    voice: line.voice === "upload" ? "Kore" : line.voice,
    delivery: line.delivery ?? "",
    pauseAfterSeconds: line.pauseAfterSeconds ?? 0.4,
  }));
}

export function GenerateWorkspace() {
  const queryClient = useQueryClient();
  const [lines, setLines] = useState<DraftLine[]>(() => [newDraftLine("Kore")]);
  const [title, setTitle] = useState("");
  const [current, setCurrent] = useState<Generation | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const [transcript, setTranscript] = useState("");
  const [historyFilter, setHistoryFilter] = useState<"all" | "unsaved" | "saved">(
    "all",
  );
  const [renameId, setRenameId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState("");
  const inFlight = useRef(false);
  const startedAt = useRef<number | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const generateRequest = useRef<{ payloadKey: string; requestId: string } | null>(
    null,
  );
  const uploadRequest = useRef<{ payloadKey: string; requestId: string } | null>(
    null,
  );

  const listQuery = useQuery({
    queryKey: QUERY_KEY,
    queryFn: generateApi.list,
  });
  const settingsQuery = useQuery({
    queryKey: ["tts-settings"],
    queryFn: () => ttsApi.getTtsSettings(),
  });

  const modelId = settingsQuery.data?.geminiTtsModel;
  const modelLabel =
    GEMINI_TTS_MODELS.find((model) => model.id === modelId)?.label ?? modelId;

  const applyTranscript = (generation: Generation) => {
    setTranscript(
      generation.transcript ?? generation.lines.map((line) => line.text).join("\n"),
    );
  };

  const remember = (
    generation: Generation,
    options: { syncTranscript?: boolean } = {},
  ) => {
    setCurrent(generation);
    if (options.syncTranscript) applyTranscript(generation);
    queryClient.setQueryData(QUERY_KEY, (prev: typeof listQuery.data) => {
      const existing = prev?.generations ?? [];
      const next = [
        generation,
        ...existing.filter((item) => item.id !== generation.id),
      ];
      return {
        generations: next,
        temporaryLifetime: prev?.temporaryLifetime ?? GENERATE_TEMPORARY_LIFETIME,
      };
    });
  };

  const generateMutation = useMutation({
    mutationFn: generateApi.create,
    onSuccess: (result) => {
      generateRequest.current = null;
      remember(result.generation, { syncTranscript: true });
      setError(null);
      if (result.reused) {
        toast.message("Reused the clip from a moment ago instead of charging twice.");
      }
    },
    onError: (err: Error) => {
      setError(err.message);
    },
    onSettled: () => {
      inFlight.current = false;
      startedAt.current = null;
    },
  });

  useEffect(() => {
    if (!generateMutation.isPending) return;
    const timer = window.setInterval(() => {
      if (startedAt.current) {
        setElapsed(Math.floor((Date.now() - startedAt.current) / 1000));
      }
    }, 250);
    return () => window.clearInterval(timer);
  }, [generateMutation.isPending]);

  const saveMutation = useMutation({
    mutationFn: (id: string) => generateApi.patch(id, { saved: true }),
    onSuccess: (result) => {
      remember(result.generation);
      toast.success("Saved to library.");
    },
    onError: (err: Error) => toast.error(err.message),
  });

  const deleteMutation = useMutation({
    mutationFn: generateApi.remove,
    onSuccess: (_data, id) => {
      if (current?.id === id) setCurrent(null);
      void queryClient.invalidateQueries({ queryKey: QUERY_KEY });
    },
    onError: (err: Error) => toast.error(err.message),
  });

  const renameMutation = useMutation({
    mutationFn: ({ id, title }: { id: string; title: string }) =>
      generateApi.patch(id, { title }),
    onSuccess: (result) => {
      remember(result.generation);
      setRenameId(null);
    },
    onError: (err: Error) => toast.error(err.message),
  });

  const alignMutation = useMutation({
    mutationFn: () => {
      if (!current) throw new Error("Generate or upload audio first.");
      return generateApi.align(current.id, transcript);
    },
    onSuccess: (result) => {
      remember(result.generation, { syncTranscript: true });
      toast.success("Timing ready.");
    },
    onError: (err: Error) => toast.error(err.message),
  });

  const uploadMutation = useMutation({
    mutationFn: generateApi.upload,
    onSuccess: (result) => {
      uploadRequest.current = null;
      remember(result.generation, { syncTranscript: true });
      setError(null);
    },
    onError: (err: Error) => toast.error(err.message),
  });

  const busy =
    generateMutation.isPending ||
    uploadMutation.isPending ||
    alignMutation.isPending;

  const onGenerate = () => {
    if (inFlight.current || generateMutation.isPending) return;
    const prepared = lines
      .map((line) => ({
        id: line.id,
        text: line.text.trim(),
        voice: line.voice,
        delivery: line.delivery.trim() || undefined,
        pauseAfterSeconds: line.pauseAfterSeconds,
      }))
      .filter((line) => line.text.length > 0);
    if (prepared.length === 0) {
      setError("Type some text first.");
      return;
    }
    const payloadKey = JSON.stringify({
      title: title.trim() || "",
      lines: prepared,
    });
    generateRequest.current = retainStableRequestId(
      generateRequest.current,
      payloadKey,
    );
    inFlight.current = true;
    startedAt.current = Date.now();
    setElapsed(0);
    setError(null);
    generateMutation.mutate({
      title: title.trim() || undefined,
      lines: prepared,
      requestId: generateRequest.current.requestId,
    });
  };

  const generations = listQuery.data?.generations ?? [];
  const filtered = generations.filter((item) => {
    if (historyFilter === "unsaved") return !item.saved;
    if (historyFilter === "saved") return item.saved;
    return true;
  });
  const lifetime =
    listQuery.data?.temporaryLifetime ?? GENERATE_TEMPORARY_LIFETIME;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Generate</h1>
          <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
            One-off spoken audio from the Studio voice library. Everyday content
            still lives in Dialogues; this is a scratch pad for a line or two.
          </p>
        </div>
        {modelLabel ? (
          <p className="text-xs text-muted-foreground">
            TTS model: {modelLabel} · Settings → Voices
          </p>
        ) : null}
      </div>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(20rem,1fr)]">
        <div className="flex min-w-0 flex-col gap-6">
          <Card>
            <CardHeader>
              <CardTitle>Editor</CardTitle>
              <CardDescription>
                One line is enough. Add more to mix voices and insert pauses.
                Delivery tags such as [softly] or [laughs] use the same Gemini
                controls as TTS Studio.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-1.5">
                <Label htmlFor="generate-title">Title (optional)</Label>
                <Input
                  id="generate-title"
                  value={title}
                  disabled={busy}
                  placeholder="Shown in recent clips"
                  onChange={(event) => setTitle(event.target.value)}
                />
              </div>
              <GenerateLines lines={lines} onChange={setLines} disabled={busy} />
              {error ? (
                <div
                  role="alert"
                  className="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
                >
                  <p>{error}</p>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="mt-2"
                    onClick={onGenerate}
                  >
                    <RefreshCw className="size-3.5" />
                    Retry
                  </Button>
                </div>
              ) : null}
              <div className="flex flex-wrap items-center gap-2">
                <Button
                  type="button"
                  disabled={busy}
                  onClick={onGenerate}
                  aria-busy={generateMutation.isPending}
                >
                  {generateMutation.isPending ? (
                    <Loader2 className="size-4 animate-spin" />
                  ) : (
                    <Sparkles className="size-4" />
                  )}
                  {generateMutation.isPending
                    ? `Generating… ${elapsed}s`
                    : "Generate audio"}
                </Button>
                <p className="text-xs text-muted-foreground">
                  Uses the configured Gemini TTS model. The button stays locked
                  while a request is in flight. Retry keeps the same request id
                  so a failed attempt is not billed twice.
                </p>
              </div>
            </CardContent>
          </Card>

          {generateMutation.isPending ? (
            <Card>
              <CardHeader>
                <CardTitle>Working</CardTitle>
                <CardDescription>
                  Synthesizing {lines.filter((line) => line.text.trim()).length}{" "}
                  line
                  {lines.filter((line) => line.text.trim()).length === 1
                    ? ""
                    : "s"}
                  , then encoding one MP3.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <Skeleton className="h-12 w-full" />
              </CardContent>
            </Card>
          ) : current ? (
            <ResultCard
              generation={current}
              transcript={transcript}
              onTranscript={setTranscript}
              onSave={() => saveMutation.mutate(current.id)}
              saving={saveMutation.isPending}
              onAlign={() => alignMutation.mutate()}
              aligning={alignMutation.isPending}
              onRegenerate={() => {
                if (inFlight.current || current.kind !== "tts") return;
                setLines(draftsFromGeneration(current));
                setTitle(current.title);
                const payloadKey = JSON.stringify({
                  title: current.title,
                  lines: current.lines,
                  regenerate: current.id,
                });
                generateRequest.current = retainStableRequestId(
                  generateRequest.current,
                  payloadKey,
                );
                inFlight.current = true;
                startedAt.current = Date.now();
                setElapsed(0);
                setError(null);
                generateMutation.mutate({
                  title: current.title,
                  lines: current.lines,
                  requestId: generateRequest.current.requestId,
                });
              }}
            />
          ) : null}

          <Card>
            <CardHeader>
              <CardTitle>Timing from a file</CardTitle>
              <CardDescription>
                Upload a clip from this device and an editable transcript. Studio
                does not fetch remote URLs. Alignment uses the same pipeline as
                TTS takes.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              <input
                ref={fileRef}
                type="file"
                accept="audio/wav,audio/mpeg,audio/mp4,audio/aac,audio/ogg,audio/flac,.wav,.mp3,.m4a,.ogg,.flac"
                className="hidden"
                onChange={(event) => {
                  const file = event.target.files?.[0];
                  event.target.value = "";
                  if (!file) return;
                  const text =
                    transcript.trim() ||
                    lines.map((line) => line.text.trim()).filter(Boolean).join("\n");
                  if (!text) {
                    toast.error("Paste a transcript before uploading.");
                    return;
                  }
                  const payloadKey = JSON.stringify({
                    name: file.name,
                    size: file.size,
                    lastModified: file.lastModified,
                    transcript: text,
                    title: title.trim() || "",
                  });
                  uploadRequest.current = retainStableRequestId(
                    uploadRequest.current,
                    payloadKey,
                  );
                  uploadMutation.mutate({
                    file,
                    transcript: text,
                    title: title.trim() || undefined,
                    requestId: uploadRequest.current.requestId,
                  });
                }}
              />
              <Button
                type="button"
                variant="outline"
                disabled={busy}
                onClick={() => fileRef.current?.click()}
              >
                {uploadMutation.isPending ? (
                  <Loader2 className="size-4 animate-spin" />
                ) : (
                  <Upload className="size-4" />
                )}
                Upload audio to time
              </Button>
            </CardContent>
          </Card>
        </div>

        <Card className="h-fit">
          <CardHeader>
            <CardTitle>Recent</CardTitle>
            <CardDescription>{lifetime}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <Tabs
              value={historyFilter}
              onValueChange={(value) =>
                value && setHistoryFilter(value as typeof historyFilter)
              }
            >
              <TabsList>
                <TabsTrigger value="all">All</TabsTrigger>
                <TabsTrigger value="unsaved">Unsaved</TabsTrigger>
                <TabsTrigger value="saved">Saved</TabsTrigger>
              </TabsList>
            </Tabs>
            {listQuery.isLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-16 w-full" />
                <Skeleton className="h-16 w-full" />
              </div>
            ) : listQuery.isError ? (
              <div role="alert" className="space-y-2 text-sm text-destructive">
                <p>
                  {listQuery.error instanceof Error
                    ? listQuery.error.message
                    : "Could not load recent clips."}
                </p>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => void listQuery.refetch()}
                >
                  Retry
                </Button>
              </div>
            ) : filtered.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                {historyFilter === "saved"
                  ? "Nothing saved to the library yet."
                  : historyFilter === "unsaved"
                    ? "No unsaved clips. Generate something to preview it here."
                    : "No clips yet. Generate a line to see it here."}
              </p>
            ) : (
              <ul className="flex flex-col gap-2">
                {filtered.map((item) => (
                  <li
                    key={item.id}
                    className={cn(
                      "rounded-lg p-3 ring-1 ring-foreground/10",
                      current?.id === item.id && "bg-accent/60",
                    )}
                  >
                    <button
                      type="button"
                      className="w-full text-left"
                      onClick={() => {
                        remember(item, { syncTranscript: true });
                        setLines(draftsFromGeneration(item));
                        setTitle(item.title);
                      }}
                    >
                      <div className="flex items-start justify-between gap-2">
                        <p className="font-medium leading-snug">{item.title}</p>
                        <Badge variant={item.saved ? "secondary" : "outline"}>
                          {item.saved
                            ? "Saved"
                            : item.expiresAt
                              ? `Unsaved · expires ${formatWhen(item.expiresAt)}`
                              : "Unsaved"}
                        </Badge>
                      </div>
                      <p className="mt-1 text-xs text-muted-foreground">
                        {formatWhen(item.createdAt)} · {formatDuration(item.durationSeconds)}
                        {item.kind === "upload" ? " · uploaded" : ""}
                      </p>
                    </button>
                    <audio
                      className="mt-2 w-full"
                      controls
                      preload="none"
                      src={item.audioUrl}
                    />
                    <div className="mt-2 flex flex-wrap gap-1">
                      <a
                        className={cn(buttonVariants({ variant: "ghost", size: "xs" }))}
                        href={item.downloadUrl}
                      >
                        <Download className="size-3.5" />
                        MP3
                      </a>
                      {!item.saved ? (
                        <Button
                          type="button"
                          variant="ghost"
                          size="xs"
                          onClick={() => saveMutation.mutate(item.id)}
                        >
                          <Save className="size-3.5" />
                          Save
                        </Button>
                      ) : null}
                      <Button
                        type="button"
                        variant="ghost"
                        size="xs"
                        onClick={() => {
                          setLines(draftsFromGeneration(item));
                          setTitle(item.title);
                          setCurrent(item);
                        }}
                      >
                        <RefreshCw className="size-3.5" />
                        Reuse
                      </Button>
                      {renameId === item.id ? (
                        <form
                          className="flex items-center gap-1"
                          onSubmit={(event) => {
                            event.preventDefault();
                            if (renameValue.trim()) {
                              renameMutation.mutate({
                                id: item.id,
                                title: renameValue.trim(),
                              });
                            }
                          }}
                        >
                          <Input
                            value={renameValue}
                            onChange={(event) => setRenameValue(event.target.value)}
                            className="h-7 w-36"
                            aria-label="New title"
                          />
                          <Button type="submit" size="xs">
                            Save
                          </Button>
                        </form>
                      ) : (
                        <Button
                          type="button"
                          variant="ghost"
                          size="xs"
                          onClick={() => {
                            setRenameId(item.id);
                            setRenameValue(item.title);
                          }}
                        >
                          <Pencil className="size-3.5" />
                          Rename
                        </Button>
                      )}
                      <Button
                        type="button"
                        variant="ghost"
                        size="xs"
                        onClick={() => {
                          if (window.confirm("Delete this clip from Studio?")) {
                            deleteMutation.mutate(item.id);
                          }
                        }}
                      >
                        <Trash2 className="size-3.5" />
                        Delete
                      </Button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

function ResultCard({
  generation,
  transcript,
  onTranscript,
  onSave,
  saving,
  onAlign,
  aligning,
  onRegenerate,
}: {
  generation: Generation;
  transcript: string;
  onTranscript: (value: string) => void;
  onSave: () => void;
  saving: boolean;
  onAlign: () => void;
  aligning: boolean;
  onRegenerate: () => void;
}) {
  const voices = useMemo(
    () =>
      [...new Set(generation.lines.map((line) => line.voice).filter((v) => v !== "upload"))],
    [generation.lines],
  );

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <CardTitle>{generation.title}</CardTitle>
            <CardDescription>
              {formatDuration(generation.durationSeconds)}
              {voices.length > 0
                ? ` · ${voices.map((voice) => geminiVoiceLabel(voice)).join(", ")}`
                : ""}
            </CardDescription>
          </div>
          <Badge variant={generation.saved ? "secondary" : "outline"}>
            {generation.saved
              ? "Saved to library"
              : generation.expiresAt
                ? `Unsaved · expires ${formatWhen(generation.expiresAt)}`
                : "Unsaved"}
          </Badge>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <audio className="w-full" controls src={generation.audioUrl} />
        <div className="flex flex-wrap gap-2">
          <a
            className={cn(buttonVariants({ variant: "outline" }))}
            href={generation.downloadUrl}
          >
            <Download className="size-4" />
            Download MP3
          </a>
          {!generation.saved ? (
            <Button type="button" onClick={onSave} disabled={saving}>
              {saving ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}
              Save to library
            </Button>
          ) : null}
          {generation.kind === "tts" ? (
            <Button type="button" variant="outline" onClick={onRegenerate}>
              <RefreshCw className="size-4" />
              Regenerate
            </Button>
          ) : null}
        </div>
        {!generation.saved ? (
          <p className="text-xs text-muted-foreground">{GENERATE_TEMPORARY_LIFETIME}</p>
        ) : null}

        <div className="space-y-2 border-t border-border/60 pt-4">
          <h2 className="text-sm font-medium">Timing</h2>
          <p className="text-xs text-muted-foreground">
            Optional. {GENERATE_ALIGNMENT_NOTE}
          </p>
          <Textarea
            value={transcript}
            onChange={(event) => onTranscript(event.target.value)}
            aria-label="Transcript for alignment"
          />
          <div className="flex flex-wrap gap-2">
            <Button
              type="button"
              variant="outline"
              onClick={onAlign}
              disabled={aligning}
            >
              {aligning ? (
                <Loader2 className="size-4 animate-spin" />
              ) : null}
              {aligning ? "Aligning…" : "Generate timing"}
            </Button>
            {generation.timingUrl ? (
              <a
                className={cn(buttonVariants({ variant: "outline" }))}
                href={generation.timingUrl}
              >
                <Download className="size-4" />
                Timing JSON
              </a>
            ) : null}
          </div>
          {generation.lineTimings && generation.lineTimings.length > 0 ? (
            <div className="overflow-x-auto rounded-md border border-border/60">
              <table className="w-full text-left text-xs">
                <caption className="sr-only">Line-level timestamps</caption>
                <thead className="bg-muted/50 text-muted-foreground">
                  <tr>
                    <th className="px-2 py-1.5 font-medium">Line</th>
                    <th className="px-2 py-1.5 font-medium">Start</th>
                    <th className="px-2 py-1.5 font-medium">End</th>
                    <th className="px-2 py-1.5 font-medium">Pause</th>
                  </tr>
                </thead>
                <tbody>
                  {generation.lineTimings.map((timing) => (
                    <tr key={timing.index} className="border-t border-border/60">
                      <td className="px-2 py-1.5">{timing.text}</td>
                      <td className="px-2 py-1.5 tabular-nums">
                        {timing.startSeconds.toFixed(2)}s
                      </td>
                      <td className="px-2 py-1.5 tabular-nums">
                        {timing.endSeconds.toFixed(2)}s
                      </td>
                      <td className="px-2 py-1.5 tabular-nums">
                        {timing.pauseAfterSeconds.toFixed(2)}s
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
          {generation.tokenSync ? (
            <div className="space-y-2">
              <p className="text-xs font-medium text-muted-foreground">
                Word timestamps
                {generation.tokenSync.alignerVersion
                  ? ` · ${generation.tokenSync.alignerVersion}`
                  : ""}
              </p>
              {generation.tokenSync.lines.map((line, lineIndex) => (
                <p key={lineIndex} className="text-sm leading-relaxed">
                  {line.tokens.map((token, tokenIndex) => (
                    <span key={`${lineIndex}-${tokenIndex}`} className="mr-1">
                      {token.text}
                      <span className="text-[10px] text-muted-foreground">
                        {token.startSeconds == null
                          ? ""
                          : ` ${token.startSeconds.toFixed(2)}`}
                      </span>
                    </span>
                  ))}
                </p>
              ))}
            </div>
          ) : null}
        </div>
      </CardContent>
    </Card>
  );
}
