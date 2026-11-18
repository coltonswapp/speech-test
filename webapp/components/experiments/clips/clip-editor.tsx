"use client";

import { useEffect, useMemo, useRef, useState, type RefObject } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  ArchiveIcon,
  ArchiveRestoreIcon,
  AudioLinesIcon,
  ChevronLeftIcon,
  ExternalLinkIcon,
  LanguagesIcon,
  Loader2Icon,
  MicIcon,
  RefreshCwIcon,
  SaveIcon,
  ScissorsIcon,
  SignalIcon,
  SparklesIcon,
  Trash2Icon,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { HighlightsEditor } from "@/components/dialogue/highlights-editor";
import type { DialogueHighlights, DialogueLine } from "@/lib/dialogue/types";
import { clipsApi } from "@/lib/experiments/clips/client";
import {
  CLIP_STEP_MODELS,
  GEMINI_ASR_MODEL_DEFAULT,
  GEMINI_TEXT_MODEL_DEFAULT,
  isClipStepModel,
} from "@/lib/gemini/models";
import {
  CLIP_JLPT_LEVELS,
  clipHasUntimedLines,
  clipIsAligned,
  clipIsTokenized,
  sentenceIsTimed,
  type ClipDraft,
  type ClipDraftResponse,
  type ClipUsageRun,
} from "@/lib/experiments/clips/types";
import {
  FEED_STATE_LABELS,
  clipFeedNotReady,
  clipFeedRules,
  clipFeedStatus,
} from "@/lib/experiments/clips/feed";
import { cn } from "@/lib/utils";
import { formatTimecode } from "@/components/experiments/clips/clip-format";
import { ClipTokenLines } from "@/components/experiments/clips/clip-token-lines";
import {
  formatCount,
  formatUSD,
  runCost,
  STEP_LABELS,
} from "@/lib/experiments/clips/usage-cost";
import {
  ClipMedia,
  type ClipMediaController,
  type ClipMediaProps,
} from "@/components/experiments/clips/clip-media";
import { EditorSection } from "@/components/experiments/clips/editor-section";
import { ClipTagsSection } from "@/components/experiments/clips/clip-tags-section";
import { ClipFeedbackSection } from "@/components/experiments/clips/clip-feedback";
import type { ClipTagPick } from "@/lib/experiments/clips/tags";
import type { EditableToken } from "@/lib/experiments/clips/token-edits";


type Step = "transcribe" | "translate" | "tokenize" | "align" | "level" | "tag" | "feed";

type ModelStep = "transcribe" | "translate";
type StepModels = Record<ModelStep, string>;

const DEFAULT_STEP_MODELS: StepModels = {
  transcribe: GEMINI_ASR_MODEL_DEFAULT,
  translate: GEMINI_TEXT_MODEL_DEFAULT,
};
const STEP_MODELS_STORAGE_KEY = "experiments.clips.stepModels";

/** Model picks for Transcribe and Translate, remembered in this browser. */
function useStepModels(): [StepModels, (step: ModelStep, model: string) => void] {
  const [models, setModels] = useState<StepModels>(DEFAULT_STEP_MODELS);
  useEffect(() => {
    try {
      const saved = JSON.parse(localStorage.getItem(STEP_MODELS_STORAGE_KEY) ?? "null");
      if (!saved || typeof saved !== "object") return;
      setModels((prev) => ({
        transcribe: isClipStepModel(saved.transcribe) ? saved.transcribe : prev.transcribe,
        translate: isClipStepModel(saved.translate) ? saved.translate : prev.translate,
      }));
    } catch {
      // Ignore unreadable storage; defaults stand.
    }
  }, []);
  const setModel = (step: ModelStep, model: string) => {
    setModels((prev) => {
      const next = { ...prev, [step]: model };
      try {
        localStorage.setItem(STEP_MODELS_STORAGE_KEY, JSON.stringify(next));
      } catch {
        // Private mode etc.: the pick still applies for this visit.
      }
      return next;
    });
  };
  return [models, setModel];
}

export function ClipEditor({ clipId }: { clipId: string }) {
  const queryClient = useQueryClient();
  const router = useRouter();
  const [stepModels, setStepModel] = useStepModels();
  const queryKey = useMemo(() => ["experiment-clip", clipId], [clipId]);
  const clipQuery = useQuery({ queryKey, queryFn: () => clipsApi.get(clipId) });
  const draft = clipQuery.data?.draft;
  const mediaRef = useRef<ClipMediaController>(null);

  const setDraft = (next: ClipDraft) => {
    queryClient.setQueryData<ClipDraftResponse>(queryKey, (prev) =>
      prev ? { ...prev, draft: next } : prev
    );
    void queryClient.invalidateQueries({ queryKey: ["experiment-clips"] });
  };

  // Transcript textarea: one sentence per line. Shows the server draft until
  // edited; `edit` holds unsaved local text (null = no local edits).
  const serverText = draft?.sentences.map((s) => s.text).join("\n") ?? "";
  const [edit, setEdit] = useState<string | null>(null);
  const text = edit ?? serverText;
  const dirty = edit !== null && edit !== serverText;
  const [savingOrientation, setSavingOrientation] = useState(false);

  const saveTranscript = useMutation({
    mutationFn: () => clipsApi.patch(clipId, { sentences: text.split("\n") }),
    onSuccess: ({ draft: next }) => {
      setEdit(null);
      setDraft(next);
      toast.success("Transcript saved.");
    },
    onError: (error) => toast.error(error.message),
  });

  const runStep = useMutation({
    mutationFn: (step: Step) =>
      clipsApi.step(
        clipId,
        step,
        step === "transcribe" || step === "translate"
          ? stepModels[step]
          : step === "level" || step === "tag"
            ? stepModels.translate // the text model picked for Translate
            : undefined
      ),
    onSuccess: ({ draft: next }, step) => {
      if (step === "transcribe") setEdit(null);
      setDraft(next);
      const tokenCount = next.sentences.reduce((n, s) => n + (s.tokens?.length ?? 0), 0);
      toast.success(
        step === "feed"
          ? FEED_STATE_LABELS[clipFeedStatus(next).state] + "."
          : step === "level"
          ? `Rated N${next.difficulty?.jlptLevel ?? "?"}.`
          : step === "tag"
          ? `Tagged ${next.tags?.auto ? [next.tags.auto.format, ...next.tags.auto.topics].join(", ") : ""}.`
          : step === "transcribe"
          ? `Transcribed ${next.sentences.length} sentences.`
          : step === "translate"
            ? `Translated ${next.sentences.length} sentences.`
          : step === "tokenize"
            ? `Tokenized ${tokenCount} tokens.`
            : `Aligned ${tokenCount} tokens.`
      );
      if (step === "tokenize") warnBasicSplits(next);
    },
    onError: (error) => toast.error(error.message),
  });

  const alignUntimed = useMutation({
    mutationFn: () => clipsApi.alignUntimed(clipId),
    onSuccess: ({ draft: next }) => {
      const before = draft?.sentences.filter((s) => !sentenceIsTimed(s)).length ?? 0;
      setDraft(next);
      toast.success(`Aligned ${before} edited ${before === 1 ? "line" : "lines"}; others unchanged.`);
    },
    onError: (error) => toast.error(error.message),
  });

  // Transcribe → tokenize → align, one request per step (each has its own
  // server time budget). Skips steps already done, never re-transcribes, and
  // keeps timed lines' timings when only some lines need aligning.
  const [runAllStep, setRunAllStep] = useState<"transcribe" | "tokenize" | "align" | null>(null);
  const runAll = useMutation({
    mutationFn: async () => {
      if (!draft) throw new Error("Clip not loaded.");
      let current = draft;
      try {
        if (current.sentences.length === 0) {
          setRunAllStep("transcribe");
          current = (await clipsApi.step(clipId, "transcribe", stepModels.transcribe)).draft;
          setEdit(null);
          setDraft(current);
        }
        if (!clipIsTokenized(current)) {
          setRunAllStep("tokenize");
          current = (await clipsApi.step(clipId, "tokenize")).draft;
          setDraft(current);
        }
        if (!clipIsAligned(current)) {
          setRunAllStep("align");
          current = clipHasUntimedLines(current)
            ? (await clipsApi.alignUntimed(clipId)).draft
            : (await clipsApi.step(clipId, "align")).draft;
          setDraft(current);
        }
      } finally {
        setRunAllStep(null);
      }
      return current;
    },
    onSuccess: (next) => {
      const tokenCount = next.sentences.reduce((n, s) => n + (s.tokens?.length ?? 0), 0);
      toast.success(`Ready: ${next.sentences.length} sentences, ${tokenCount} tokens aligned.`);
      warnBasicSplits(next);
    },
    onError: (error) => toast.error(error.message),
  });

  const refreshVideoInfo = useMutation({
    mutationFn: () => clipsApi.videoInfo(clipId),
    onSuccess: ({ draft: next }) => {
      setDraft(next);
      toast.success(`${next.video?.title ?? clipId} · ${next.video?.channelName ?? ""}`);
    },
    onError: (error) => toast.error(error.message),
  });

  const setLevel = useMutation({
    mutationFn: (jlptLevel: number | null) => clipsApi.patch(clipId, { jlptLevel }),
    onSuccess: ({ draft: next }) => setDraft(next),
    onError: (error) => toast.error(error.message),
  });

  const setFeed = useMutation({
    mutationFn: (feedEligible: boolean | null) => clipsApi.patch(clipId, { feedEligible }),
    onSuccess: ({ draft: next }) => setDraft(next),
    onError: (error) => toast.error(error.message),
  });

  const setTags = useMutation({
    mutationFn: (tags: ClipTagPick | null) => clipsApi.patch(clipId, { tags }),
    onSuccess: ({ draft: next }) => {
      setDraft(next);
      toast.success(next.tags?.manual ? "Tags saved." : "Back to the Tag step’s tags.");
    },
    onError: (error) => toast.error(error.message),
  });

  const setDeprecated = useMutation({
    mutationFn: (deprecated: { reason?: string } | null) =>
      clipsApi.patch(clipId, { deprecated }),
    onSuccess: ({ draft: next }) => {
      setDraft(next);
      toast.success(
        next.deprecated
          ? `Deprecated ${clipId}. It is out of the app’s clip list; its transcript is kept.`
          : `Restored ${clipId}.`
      );
    },
    onError: (error) => toast.error(error.message),
  });

  const deleteClip = useMutation({
    mutationFn: () => clipsApi.delete(clipId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["experiment-clips"] });
      toast.success(`Deleted ${clipId}.`);
      router.push("/experiments/clips");
    },
    onError: (error) => toast.error(error.message),
  });

  if (clipQuery.isPending) return <Skeleton className="h-64 w-full" />;
  if (clipQuery.isError || !draft) {
    return (
      <p className="text-sm text-destructive">
        {clipQuery.error?.message ?? "Clip not found."}
      </p>
    );
  }

  const tokenized = clipIsTokenized(draft);
  const aligned = clipIsAligned(draft);
  const partlyAligned = clipHasUntimedLines(draft);
  const busyStep = runStep.isPending ? runStep.variables : null;
  const busy =
    runStep.isPending || saveTranscript.isPending || alignUntimed.isPending || runAll.isPending;
  const audioUrl = clipQuery.data?.audioUrl ?? "";
  // One player for the page (right column); Review drives it for token sync.
  const mediaProps: ClipMediaProps = {
    videoId: draft.videoId,
    startSec: draft.startSec,
    endSec: draft.endSec,
    portrait: draft.orientation === "portrait",
    audioUrl,
  };
  const youtubeUrl = `https://www.youtube.com/watch?v=${draft.videoId}&t=${Math.floor(draft.startSec)}s`;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <Link
          href="/experiments/clips"
          className="mb-1 inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
        >
          <ChevronLeftIcon className="size-3" /> Clips
        </Link>
        <h1 className="flex items-center gap-2 font-mono text-xl font-semibold tracking-tight">
          {draft.id}
          {aligned ? (
            <a href={`/api/public/clips/${draft.id}`} target="_blank" rel="noreferrer">
              {draft.deprecated ? (
                <Badge
                  variant="destructive"
                  className="font-sans"
                  title={draft.deprecated.reason ?? "No reason given"}
                >
                  Deprecated
                </Badge>
              ) : (
                <Badge variant="secondary" className="font-sans">
                  Live in app
                </Badge>
              )}
            </a>
          ) : draft.deprecated ? (
            <Badge variant="destructive" className="font-sans">
              Deprecated
            </Badge>
          ) : null}
          {draft.difficulty ? (
            <Badge variant="outline" className="font-sans">
              N{draft.difficulty.jlptLevel}
            </Badge>
          ) : null}
        </h1>
        <p className="flex flex-wrap items-center gap-x-2 text-sm">
          {draft.video ? (
            <>
              <span className="font-medium">{draft.video.title}</span>
              {draft.video.titleEn ? (
                <span className="text-muted-foreground" title={`English title (${draft.video.titleEn.model})`}>
                  {draft.video.titleEn.text}
                </span>
              ) : null}
              {draft.video.channelUrl ? (
                <a
                  href={draft.video.channelUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="text-muted-foreground hover:text-foreground"
                >
                  {draft.video.channelName}
                </a>
              ) : (
                <span className="text-muted-foreground">{draft.video.channelName}</span>
              )}
            </>
          ) : (
            <span className="text-muted-foreground">No video title or channel yet.</span>
          )}
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="text-muted-foreground"
            disabled={refreshVideoInfo.isPending}
            title="Fetch the video’s title and channel from YouTube (and translate the title if it changed). Fails if the video is deleted, private or not embeddable."
            onClick={() => refreshVideoInfo.mutate()}
          >
            {refreshVideoInfo.isPending ? <Loader2Icon className="animate-spin" /> : <RefreshCwIcon />}
            {draft.video ? "Refresh" : "Get from YouTube"}
          </Button>
        </p>
        <p className="flex flex-wrap items-center gap-x-2 text-sm text-muted-foreground">
          <a
            href={youtubeUrl}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1 hover:text-foreground"
          >
            {draft.videoId} <ExternalLinkIcon className="size-3" />
          </a>
          <Link
            href={`/experiments/clips/video/${draft.videoId}`}
            className="hover:text-foreground"
            title="Every clip from this video on one page, following the video"
          >
            · All clips from this video
          </Link>
          <span>
            {formatTimecode(draft.startSec)}–{formatTimecode(draft.endSec)} (
            {draft.durationSec.toFixed(1)} s)
          </span>
          {draft.asr ? <span>· ASR {draft.asr.model}</span> : null}
          {draft.translation ? <span>· EN {draft.translation.model}</span> : null}
          {draft.alignment ? <span>· {draft.alignment.alignerVersion}</span> : null}
          <span className="inline-flex items-center gap-1.5">
            ·
            <Switch
              id="clip-vertical"
              checked={draft.orientation === "portrait"}
              disabled={busy || savingOrientation}
              onCheckedChange={async (vertical) => {
                setSavingOrientation(true);
                try {
                  const { draft: next } = await clipsApi.patch(clipId, {
                    orientation: vertical ? "portrait" : "landscape",
                  });
                  setDraft(next);
                } catch (error) {
                  toast.error(error instanceof Error ? error.message : String(error));
                } finally {
                  setSavingOrientation(false);
                }
              }}
            />
            <Label htmlFor="clip-vertical" className="text-sm font-normal text-muted-foreground">
              Vertical Short
            </Label>
          </span>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="ml-auto text-muted-foreground"
            disabled={busy || setDeprecated.isPending || deleteClip.isPending}
            title={
              draft.deprecated
                ? "Put the clip back in the app’s clip list"
                : "Take the clip out of the app’s clip list (video deleted or delisted, bad clip) but keep its transcript for anything saved from it"
            }
            onClick={() => {
              if (draft.deprecated) {
                setDeprecated.mutate(null);
                return;
              }
              const reason = window.prompt(
                `Deprecate ${draft.id}? It leaves the app’s clip list; its transcript stays available to items saved from it.\n\nReason (optional), e.g. “video deleted”:`,
                ""
              );
              if (reason !== null) setDeprecated.mutate({ reason: reason.trim() || undefined });
            }}
          >
            {setDeprecated.isPending ? (
              <Loader2Icon className="animate-spin" />
            ) : draft.deprecated ? (
              <ArchiveRestoreIcon />
            ) : (
              <ArchiveIcon />
            )}
            {draft.deprecated ? "Restore" : "Deprecate"}
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="text-muted-foreground hover:text-destructive"
            disabled={busy || deleteClip.isPending}
            onClick={() => {
              const warning = aligned
                ? `Delete ${draft.id}? It is live in the app: it disappears, and anything saved from it loses its transcript. To retire a clip but keep that, use Deprecate instead. This can’t be undone.`
                : `Delete ${draft.id}? Its audio and transcript are removed and the id can be reused. This can’t be undone.`;
              if (window.confirm(warning)) deleteClip.mutate();
            }}
          >
            {deleteClip.isPending ? <Loader2Icon className="animate-spin" /> : <Trash2Icon />}
            Delete clip
          </Button>
        </p>
      </div>

      {/* Sections on the left; the player stays put on the right (above them on narrow screens). */}
      <div className="flex flex-col gap-6 lg:grid lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start">
      <aside className="lg:sticky lg:top-20 lg:col-start-2 lg:row-start-1">
        <div className="rounded-xl border border-border/60 p-3">
          <ClipMedia {...mediaProps} controllerRef={mediaRef} preload="auto" />
        </div>
      </aside>
      <div className="flex min-w-0 flex-col gap-6 lg:col-start-1 lg:row-start-1">

      <EditorSection id="models" title="Models" defaultOpen={false}>
        <div className="flex flex-wrap items-end gap-4">
          <p className="mr-auto text-xs text-muted-foreground">
            Used the next time you run that step. The header shows which model made the current
            transcript and English.
          </p>
          <ModelPicker
            label="Transcribe"
            value={stepModels.transcribe}
            disabled={busy}
            onChange={(model) => setStepModel("transcribe", model)}
          />
          <ModelPicker
            label="Translate"
            value={stepModels.translate}
            disabled={busy}
            onChange={(model) => setStepModel("translate", model)}
          />
        </div>
      </EditorSection>

      {aligned ? null : (
        <section className="flex flex-wrap items-center gap-3 rounded-xl border border-border/60 p-4">
          <Button
            disabled={busy || dirty}
            onClick={() => runAll.mutate()}
          >
            {runAll.isPending ? <Loader2Icon className="animate-spin" /> : <AudioLinesIcon />}
            {runAll.isPending
              ? runAllStep === "transcribe"
                ? "Transcribing…"
                : runAllStep === "tokenize"
                  ? "Tokenizing…"
                  : "Aligning…"
              : "Run all steps"}
          </Button>
          <p className="text-xs text-muted-foreground">
            {dirty
              ? "Save the transcript first."
              : "Transcribe, tokenize and align, skipping whatever is already done. English and highlights stay separate."}
          </p>
        </section>
      )}

      {/* 1. Transcript */}
      <EditorSection
        id="transcript"
        title="1. Transcript"
        summary={`${draft.sentences.length} sentences${dirty ? " · unsaved" : ""}`}
        actions={
          <>
            <Button
              variant="outline"
              size="sm"
              disabled={busy}
              onClick={() => {
                if (
                  draft.sentences.length > 0 &&
                  !window.confirm("Replace the current transcript with a fresh ASR pass?")
                ) {
                  return;
                }
                runStep.mutate("transcribe");
              }}
            >
              {busyStep === "transcribe" ? <Loader2Icon className="animate-spin" /> : <MicIcon />}
              {draft.sentences.length > 0 ? "Re-transcribe" : "Transcribe"}
            </Button>
            <Button size="sm" disabled={!dirty || busy} onClick={() => saveTranscript.mutate()}>
              {saveTranscript.isPending ? <Loader2Icon className="animate-spin" /> : <SaveIcon />}
              Save
            </Button>
          </>
        }
      >
        <Textarea
          value={text}
          onChange={(e) => setEdit(e.target.value)}
          rows={Math.min(16, Math.max(6, text.split("\n").length + 1))}
          placeholder="Run ASR, or paste the transcript: one sentence per line."
          className="text-base leading-relaxed"
          lang="ja"
        />
        <p className="text-xs text-muted-foreground">
          One sentence per line, exactly as spoken. Saving clears all timings; edited lines are
          re-tokenized.
        </p>
      </EditorSection>

      {/* 2. English */}
      <EnglishSection
        key={draft.sentences.map((s) => `${s.text}\u0001${s.en ?? ""}`).join("\u0002")}
        draft={draft}
        disabled={busy || dirty}
        translating={busyStep === "translate"}
        onTranslate={() => {
          if (
            draft.sentences.some((s) => s.en?.trim()) &&
            !window.confirm("Replace all English with a fresh translation?")
          ) {
            return;
          }
          runStep.mutate("translate");
        }}
        onSave={async (english) => {
          try {
            const { draft: next } = await clipsApi.patch(clipId, { english });
            setDraft(next);
            toast.success("English saved.");
          } catch (error) {
            toast.error(error instanceof Error ? error.message : String(error));
          }
        }}
      />

      {/* 3 + 4. Tokenize, align */}
      <EditorSection
        id="tokenize-align"
        title="3–4. Tokenize and align"
        summary={aligned ? "aligned" : partlyAligned ? "some lines need aligning" : tokenized ? "tokenized" : ""}
      >
      <div className="flex flex-wrap items-end gap-3">
        <div className="flex flex-col gap-1.5">
          <h3 className="text-sm font-medium">3. Tokenize</h3>
          <Button
            variant={tokenized ? "outline" : "default"}
            size="sm"
            disabled={busy || dirty || draft.sentences.length === 0 || tokenized}
            onClick={() => runStep.mutate("tokenize")}
          >
            {busyStep === "tokenize" ? <Loader2Icon className="animate-spin" /> : <ScissorsIcon />}
            {tokenized ? "Tokenized" : "Tokenize"}
          </Button>
        </div>
        <div className="flex flex-col gap-1.5">
          <h3 className="text-sm font-medium">4. Timestamps</h3>
          <div className="flex gap-2">
            {partlyAligned ? (
              <Button
                size="sm"
                disabled={busy || dirty}
                onClick={() => alignUntimed.mutate()}
                title="Times only the lines you edited; every other line keeps its timings."
              >
                {alignUntimed.isPending ? (
                  <Loader2Icon className="animate-spin" />
                ) : (
                  <AudioLinesIcon />
                )}
                Align edited lines
              </Button>
            ) : null}
            <Button
              variant={aligned || partlyAligned ? "outline" : "default"}
              size="sm"
              disabled={busy || dirty || !tokenized}
              onClick={() => runStep.mutate("align")}
            >
              {busyStep === "align" ? <Loader2Icon className="animate-spin" /> : <AudioLinesIcon />}
              {aligned ? "Re-align" : partlyAligned ? "Re-align all" : "Align"}
            </Button>
          </div>
        </div>
        <ShiftField
          key={draft.shiftSec}
          shiftSec={draft.shiftSec}
          disabled={busy}
          onSave={async (shiftSec) => {
            try {
              const { draft: next } = await clipsApi.patch(clipId, { shiftSec });
              setDraft(next);
            } catch (error) {
              toast.error(error instanceof Error ? error.message : String(error));
            }
          }}
        />
        {dirty ? (
          <p className="text-xs text-amber-600 dark:text-amber-400">
            Save the transcript first.
          </p>
        ) : null}
      </div>
      </EditorSection>

      {/* 5. Highlights */}
      <ClipHighlightsSection
        key={`${draft.id}:${JSON.stringify(draft.highlights ?? null)}`}
        draft={draft}
        disabled={busy || dirty}
        onSave={async (highlights) => {
          try {
            const { draft: next } = await clipsApi.patch(clipId, { highlights });
            setDraft(next);
            toast.success("Highlights saved.");
          } catch (error) {
            toast.error(error instanceof Error ? error.message : String(error));
          }
        }}
      />

      {tokenized ? (
        <TimingReview
          draft={draft}
          audioUrl={audioUrl}
          mediaRef={mediaRef}
          disabled={busy}
          onClearFlags={async (sentence, cleared) => {
            try {
              const { draft: next } = await clipsApi.patch(clipId, {
                clearFlags: { sentence, cleared },
              });
              setDraft(next);
            } catch (error) {
              toast.error(error instanceof Error ? error.message : String(error));
            }
          }}
          onEditTokens={async (sentence, tokens) => {
            try {
              const { draft: next } = await clipsApi.patch(clipId, {
                tokens: { sentence, tokens },
              });
              setDraft(next);
              const lineTimed = sentenceIsTimed(next.sentences[sentence] ?? { text: "", tokens: [] });
              toast.success(
                aligned && !lineTimed
                  ? `Line ${sentence + 1} updated. Align edited lines to time the new tokens.`
                  : `Line ${sentence + 1} updated.`
              );
            } catch (error) {
              toast.error(error instanceof Error ? error.message : String(error));
            }
          }}
        />
      ) : null}

      <EditorSection
        id="level"
        title="6. Level"
        summary={draft.difficulty ? `N${draft.difficulty.jlptLevel}` : "not rated"}
        actions={
          <Button
            size="sm"
            variant="outline"
            disabled={busy || dirty || draft.sentences.length === 0}
            title={
              draft.difficulty?.source === "manual"
                ? "Replaces the level you set by hand"
                : "Rate the transcript’s JLPT level with the Translate model"
            }
            onClick={() => {
              if (
                draft.difficulty?.source === "manual" &&
                !window.confirm(`Replace the hand-set N${draft.difficulty.jlptLevel} with an estimate?`)
              ) {
                return;
              }
              runStep.mutate("level");
            }}
          >
            {busyStep === "level" ? <Loader2Icon className="animate-spin" /> : <SignalIcon />}
            {draft.difficulty ? "Re-estimate" : "Estimate level"}
          </Button>
        }
      >
        <div className="flex flex-wrap items-center gap-3">
          <Select
            value={draft.difficulty ? String(draft.difficulty.jlptLevel) : "none"}
            disabled={busy || setLevel.isPending}
            onValueChange={(value) => setLevel.mutate(value === "none" ? null : Number(value))}
          >
            <SelectTrigger className="w-32" aria-label="JLPT level">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="none">Not rated</SelectItem>
              {CLIP_JLPT_LEVELS.map((level) => (
                <SelectItem key={level} value={String(level)}>
                  N{level}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <p className="min-w-0 flex-1 text-xs text-muted-foreground">
            {draft.difficulty
              ? draft.difficulty.source === "manual"
                ? "Set by hand."
                : `Estimated by ${draft.difficulty.model ?? "Gemini"}${
                    draft.difficulty.reason ? `: ${draft.difficulty.reason}` : "."
                  }`
              : "Not rated yet, so the app leaves this clip out when it filters by learner level."}
          </p>
        </div>
        <p className="text-xs text-muted-foreground">
          The app shows a learner clips at their level or easier: an N5 learner only sees N5 clips,
          an N3 learner sees N5 to N3.
        </p>
      </EditorSection>

      <ClipTagsSection
        draft={draft}
        disabled={busy || dirty || setTags.isPending}
        tagging={busyStep === "tag"}
        saving={setTags.isPending}
        onTag={() => runStep.mutate("tag")}
        onSave={(tags) => setTags.mutateAsync(tags)}
      />

      <FeedSection
        draft={draft}
        disabled={busy || dirty || setFeed.isPending}
        checking={busyStep === "feed"}
        onCheck={() => runStep.mutate("feed")}
        onSetManual={(eligible) => setFeed.mutate(eligible)}
      />

      <ClipFeedbackSection clipId={clipId} />

      <UsageSection runs={draft.usage ?? []} />
      </div>
      </div>
    </div>
  );
}

/** Toast naming lines that fell back to a plain word split during tokenize. */
function warnBasicSplits(draft: ClipDraft) {
  const lines = draft.sentences.flatMap((s, i) => (s.basicSplit ? [i + 1] : []));
  if (lines.length === 0) return;
  toast.warning(
    `Line${lines.length === 1 ? "" : "s"} ${lines.join(", ")}: Gemini couldn't segment, so ${lines.length === 1 ? "it got" : "they got"} a basic word split. Check the tokens in Review.`
  );
}

/**
 * Whether the app's feed shows this clip: the measured rules with what the
 * clip scored, the Feed step's verdict, and a hand-set answer that beats both.
 */
function FeedSection({
  draft,
  disabled,
  checking,
  onCheck,
  onSetManual,
}: {
  draft: ClipDraft;
  disabled: boolean;
  checking: boolean;
  onCheck: () => void;
  onSetManual: (eligible: boolean | null) => void;
}) {
  const status = clipFeedStatus(draft);
  const notReady = clipFeedNotReady(draft);
  const rules = clipFeedRules(draft);
  const rulesPass = rules.every((rule) => rule.ok);
  const auto = draft.feed?.auto;
  const manual = draft.feed?.manual;
  return (
    <EditorSection
      id="feed"
      title="8. Feed"
      summary={FEED_STATE_LABELS[status.state].toLowerCase()}
      actions={
        <Button
          size="sm"
          variant="outline"
          disabled={disabled || notReady !== null}
          title={
            notReady
              ? `${notReady} Align and translate first.`
              : rulesPass
                ? "Ask Gemini whether this clip stands on its own and is worth showing"
                : "The clip fails a rule below, so it is turned down without asking Gemini"
          }
          onClick={onCheck}
        >
          {checking ? <Loader2Icon className="animate-spin" /> : <SparklesIcon />}
          {auto ? "Check again" : "Check for feed"}
        </Button>
      }
    >
      <div className="flex flex-wrap items-center gap-3">
        <Select
          value={manual ? (manual.eligible ? "in" : "out") : "auto"}
          disabled={disabled}
          onValueChange={(value) => onSetManual(value === "auto" ? null : value === "in")}
        >
          <SelectTrigger className="w-44" aria-label="Feed">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="auto">Automatic</SelectItem>
            <SelectItem value="in">Always in the feed</SelectItem>
            <SelectItem value="out">Never in the feed</SelectItem>
          </SelectContent>
        </Select>
        <p className="min-w-0 flex-1 text-sm">
          <span className="font-medium">{FEED_STATE_LABELS[status.state]}.</span>{" "}
          <span className="text-muted-foreground">
            {manual
              ? "Your answer overrides the rules and the check below."
              : status.reason ?? ""}
          </span>
        </p>
      </div>
      <ul className="flex flex-col gap-1 text-xs">
        {rules.map((rule) => (
          <li key={rule.label} className="flex flex-wrap gap-x-2">
            <span className={rule.ok ? "text-muted-foreground" : "font-medium text-destructive"}>
              {rule.ok ? "Passes" : "Fails"}
            </span>
            <span>{rule.label}</span>
            <span className="text-muted-foreground tabular-nums">{rule.value}</span>
          </li>
        ))}
        <li className="flex flex-wrap gap-x-2">
          <span
            className={
              auto?.model && !auto.eligible ? "font-medium text-destructive" : "text-muted-foreground"
            }
          >
            {auto?.model ? (auto.eligible ? "Passes" : "Fails") : "Not run"}
          </span>
          <span>Stands on its own and is worth watching</span>
          <span className="text-muted-foreground">
            {auto?.model
              ? `${auto.model}${auto.reason ? `: ${auto.reason}` : ""}`
              : rulesPass
                ? "Gemini reads the transcript and its English."
                : "Skipped while a rule above fails."}
          </span>
        </li>
      </ul>
      <p className="text-xs text-muted-foreground">
        Every aligned clip can be opened in the app; the feed only takes clips that pass all of
        these. Editing the transcript clears the check, so run it again afterwards.
      </p>
    </EditorSection>
  );
}

/** Every Transcribe / Translate / Tokenize / Align / Level / Tag / Feed run on this clip, newest first. */
function UsageSection({ runs }: { runs: ClipUsageRun[] }) {
  const newestFirst = [...runs].reverse();
  const costs = newestFirst.map(runCost);
  const total = costs.reduce((sum, c) => sum + (c?.usd ?? 0), 0);
  const totalIsFloor = costs.some((c) => c?.floor);
  const totals = runs.reduce(
    (t, r) => ({
      input: t.input + r.inputTokens,
      output: t.output + r.outputTokens,
      thinking: t.thinking + r.thinkingTokens,
    }),
    { input: 0, output: 0, thinking: 0 }
  );

  return (
    <EditorSection
      id="usage"
      title="Usage"
      summary={runs.length > 0 ? `${runs.length} runs · ${totalIsFloor ? "≥ " : ""}${formatUSD(total)}` : ""}
      defaultOpen={false}
    >
      <div>
        <p className="text-xs text-muted-foreground">
          Gemini tokens per run. Costs use published text rates; thinking is billed as output.
          Highlights runs aren’t logged yet.
        </p>
      </div>
      {runs.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          No runs logged yet. Runs from before usage tracking aren’t shown.
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-xs tabular-nums">
            <thead className="text-left text-muted-foreground">
              <tr className="border-b border-border/60">
                <th className="py-1.5 pr-3 font-medium">Step</th>
                <th className="py-1.5 pr-3 font-medium">Model</th>
                <th className="py-1.5 pr-3 font-medium">When</th>
                <th className="py-1.5 pr-3 text-right font-medium">Time</th>
                <th className="py-1.5 pr-3 text-right font-medium">Calls</th>
                <th className="py-1.5 pr-3 text-right font-medium">Input</th>
                <th className="py-1.5 pr-3 text-right font-medium">Output</th>
                <th className="py-1.5 pr-3 text-right font-medium">Thinking</th>
                <th className="py-1.5 text-right font-medium">Est. cost</th>
              </tr>
            </thead>
            <tbody>
              {newestFirst.map((run, i) => {
                const cost = costs[i];
                const gemini = run.step !== "align";
                return (
                  <tr key={`${run.at}-${i}`} className="border-b border-border/40 last:border-0">
                    <td className="py-1.5 pr-3 font-medium">{STEP_LABELS[run.step]}</td>
                    <td className="py-1.5 pr-3 font-mono">{run.model}</td>
                    <td className="py-1.5 pr-3 text-muted-foreground">
                      {new Date(run.at).toLocaleString(undefined, {
                        month: "short",
                        day: "numeric",
                        hour: "numeric",
                        minute: "2-digit",
                      })}
                    </td>
                    <td className="py-1.5 pr-3 text-right">{(run.durationMs / 1000).toFixed(1)} s</td>
                    <td className="py-1.5 pr-3 text-right">
                      {gemini ? formatCount(run.calls) : "—"}
                      {run.cachedLines ? (
                        <span className="block text-muted-foreground">
                          {run.cachedLines} of {run.lines} lines cached
                        </span>
                      ) : null}
                    </td>
                    <td className="py-1.5 pr-3 text-right">
                      {gemini ? formatCount(run.inputTokens) : "—"}
                      {run.audioInputTokens > 0 ? (
                        <span className="block text-muted-foreground">
                          {formatCount(run.audioInputTokens)} audio
                        </span>
                      ) : null}
                    </td>
                    <td className="py-1.5 pr-3 text-right">
                      {gemini ? formatCount(run.outputTokens) : "—"}
                    </td>
                    <td className="py-1.5 pr-3 text-right">
                      {!gemini
                        ? "—"
                        : run.step === "tokenize"
                          ? "in output"
                          : formatCount(run.thinkingTokens)}
                    </td>
                    <td className="py-1.5 text-right">
                      {cost ? `${cost.floor ? "≥ " : ""}${formatUSD(cost.usd)}` : "—"}
                    </td>
                  </tr>
                );
              })}
            </tbody>
            <tfoot>
              <tr className="border-t border-border/60 font-medium">
                <td className="py-1.5 pr-3" colSpan={5}>
                  All {runs.length} run{runs.length === 1 ? "" : "s"}
                </td>
                <td className="py-1.5 pr-3 text-right">{formatCount(totals.input)}</td>
                <td className="py-1.5 pr-3 text-right">{formatCount(totals.output)}</td>
                <td className="py-1.5 pr-3 text-right">{formatCount(totals.thinking)}</td>
                <td className="py-1.5 text-right">
                  {totalIsFloor ? "≥ " : ""}
                  {formatUSD(total)}
                </td>
              </tr>
            </tfoot>
          </table>
          {totalIsFloor ? (
            <p className="mt-2 text-xs text-muted-foreground">
              ≥: the run sent audio, which Gemini bills above the text rate used here.
            </p>
          ) : null}
        </div>
      )}
    </EditorSection>
  );
}

/**
 * One editable English line under each Japanese sentence. Remounted (via key)
 * whenever the saved transcript or English changes, so local edits reset.
 */
function EnglishSection({
  draft,
  disabled,
  translating,
  onTranslate,
  onSave,
}: {
  draft: ClipDraft;
  disabled: boolean;
  translating: boolean;
  onTranslate: () => void;
  onSave: (english: string[]) => Promise<void>;
}) {
  const saved = draft.sentences.map((s) => s.en ?? "");
  const [english, setEnglish] = useState(saved);
  const [saving, setSaving] = useState(false);
  const changed = english.some((line, i) => line !== saved[i]);
  const hasTranscript = draft.sentences.length > 0;

  return (
    <EditorSection
      id="english"
      title="2. English"
      summary={`${saved.filter((line) => line.trim()).length} of ${saved.length} translated${changed ? " · unsaved" : ""}`}
      actions={
        <>
          <Button
            variant="outline"
            size="sm"
            disabled={disabled || translating || !hasTranscript}
            onClick={onTranslate}
          >
            {translating ? <Loader2Icon className="animate-spin" /> : <LanguagesIcon />}
            {saved.some((line) => line.trim()) ? "Re-translate" : "Translate"}
          </Button>
          <Button
            size="sm"
            disabled={disabled || saving || !changed}
            onClick={async () => {
              setSaving(true);
              await onSave(english);
              setSaving(false);
            }}
          >
            {saving ? <Loader2Icon className="animate-spin" /> : <SaveIcon />}
            Save
          </Button>
        </>
      }
    >
      {hasTranscript ? (
        <ol className="flex flex-col gap-3">
          {draft.sentences.map((sentence, i) => (
            <li key={i} className="flex flex-col gap-1">
              <p className="text-sm text-muted-foreground" lang="ja">
                {sentence.text}
              </p>
              <Input
                value={english[i] ?? ""}
                placeholder="English"
                disabled={disabled}
                onChange={(e) =>
                  setEnglish((prev) => prev.map((line, j) => (j === i ? e.target.value : line)))
                }
              />
            </li>
          ))}
        </ol>
      ) : (
        <p className="text-sm text-muted-foreground">Transcribe first.</p>
      )}
      <p className="text-xs text-muted-foreground">
        One Gemini call translates the whole transcript with context. Editing a Japanese line
        clears its English; timings don’t.
      </p>
    </EditorSection>
  );
}

/** Drop blank vocab rows / notes and empty pattern labels before saving. */
function cleanHighlights(value: DialogueHighlights): DialogueHighlights | null {
  const vocabulary = (value.vocabulary ?? []).map((v) => v.trim()).filter(Boolean);
  const grammarPatterns = (value.grammarPatterns ?? []).filter(
    (pattern) => pattern.label?.trim() || pattern.patternId
  );
  const contextNotes = (value.contextNotes ?? []).map((n) => n.trim()).filter(Boolean);
  if (vocabulary.length === 0 && grammarPatterns.length === 0 && contextNotes.length === 0) {
    return null;
  }
  return { vocabulary, grammarPatterns, contextNotes };
}

/**
 * Lesson-style VOCAB / GRAMMAR / notes for the clip, edited with the same
 * HighlightsEditor as scenes: add rows by hand, or "Extract with AI" from the
 * transcript (English included when translated). Sentences stand in for
 * dialogue lines, so pattern source lines are sentence indices.
 */
function ClipHighlightsSection({
  draft,
  disabled,
  onSave,
}: {
  draft: ClipDraft;
  disabled: boolean;
  onSave: (highlights: DialogueHighlights | null) => Promise<void>;
}) {
  const saved = draft.highlights ?? null;
  const [value, setValue] = useState<DialogueHighlights | null>(saved);
  const [saving, setSaving] = useState(false);
  const cleaned = value ? cleanHighlights(value) : null;
  const changed = JSON.stringify(cleaned) !== JSON.stringify(saved ? cleanHighlights(saved) : null);

  const lines = useMemo<DialogueLine[]>(
    () =>
      draft.sentences.map((sentence) => ({
        speaker: "",
        japanese: sentence.text,
        ...(sentence.en ? { english: sentence.en } : {}),
      })),
    [draft.sentences]
  );

  return (
    <EditorSection
      id="highlights"
      title="5. Highlights"
      summary={changed ? "unsaved" : saved ? "saved" : "none"}
      actions={
        <Button
          size="sm"
          disabled={disabled || saving || !changed}
          onClick={async () => {
            setSaving(true);
            await onSave(cleaned);
            setSaving(false);
          }}
        >
          {saving ? <Loader2Icon className="animate-spin" /> : <SaveIcon />}
          Save
        </Button>
      }
    >
      {draft.sentences.length > 0 ? (
        <div className={cn(disabled && "pointer-events-none opacity-60")}>
          <HighlightsEditor
            highlights={value}
            onChange={setValue}
            lines={lines}
            setting="A short clip from a real YouTube video: natural, unscripted Japanese."
            menuTitle={draft.id}
          />
        </div>
      ) : (
        <p className="text-sm text-muted-foreground">Transcribe first.</p>
      )}
      <p className="text-xs text-muted-foreground">
        Shown in the app under the transcript, like a lesson scene’s highlights. Translate first
        for better AI picks.
      </p>
    </EditorSection>
  );
}

function ShiftField({
  shiftSec,
  disabled,
  onSave,
}: {
  shiftSec: number;
  disabled: boolean;
  onSave: (shiftSec: number) => Promise<void>;
}) {
  const [value, setValue] = useState(String(shiftSec));
  const parsed = Number(value);
  const changed = Number.isFinite(parsed) && parsed !== shiftSec;
  return (
    <div className="flex flex-col gap-1.5">
      <Label htmlFor="clip-shift">Onset shift (s)</Label>
      <div className="flex gap-1.5">
        <Input
          id="clip-shift"
          className="h-7 w-24"
          inputMode="decimal"
          value={value}
          onChange={(e) => setValue(e.target.value)}
        />
        <Button
          size="sm"
          variant="outline"
          disabled={disabled || !changed}
          onClick={() => void onSave(parsed)}
        >
          Set
        </Button>
      </div>
    </div>
  );
}

/**
 * Plays clip.wav or the YouTube video and highlights the token under the
 * playhead. Times shown are video time (startSec + aligned + shift); click a
 * token to play from it.
 */
function TimingReview({
  draft,
  audioUrl,
  mediaRef,
  disabled,
  onEditTokens,
  onClearFlags,
}: {
  draft: ClipDraft;
  /** clip.wav, for the pinned audio player. */
  audioUrl: string;
  /** The page's player (right column). */
  mediaRef: RefObject<ClipMediaController | null>;
  disabled: boolean;
  onEditTokens: (sentence: number, tokens: EditableToken[]) => Promise<void>;
  onClearFlags: (sentence: number, cleared: boolean) => Promise<void>;
}) {
  /** Audio time (shifted) at which line playback pauses; null = play on. */
  const stopAtRef = useRef<number | null>(null);
  const [active, setActive] = useState<string | null>(null);
  // Edit mode: clicking a token opens the split / merge / reading menu
  // instead of playing from it.
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);

  // Flat, time-ordered list for the playhead lookup (clip-relative + shift).
  const timeline = useMemo(() => {
    const items: Array<{ key: string; start: number; end: number }> = [];
    draft.sentences.forEach((sentence, i) =>
      (sentence.tokens ?? []).forEach((token, j) => {
        if (token.startSec === undefined || token.endSec === undefined) return;
        items.push({
          key: `${i}:${j}`,
          start: token.startSec + draft.shiftSec,
          end: token.endSec + draft.shiftSec,
        });
      })
    );
    return items;
  }, [draft]);

  // Two players: the clip audio pinned in this section's header, and the
  // page player (YouTube by default) on the right. Highlighting, token clicks
  // and Space follow whichever was played last ("driver"); starting one
  // pauses the other.
  const audioRef = useRef<HTMLAudioElement>(null);
  const driverRef = useRef<"audio" | "page">("audio");
  const audioStartedAtRef = useRef(0);
  const [rate, setRate] = useState(1);

  const audioController: ClipMediaController = useMemo(
    () => ({
      currentTime: () => audioRef.current?.currentTime ?? 0,
      paused: () => audioRef.current?.paused ?? true,
      play(clipSeconds) {
        const audio = audioRef.current;
        if (!audio) return;
        if (clipSeconds !== undefined) audio.currentTime = Math.max(0, clipSeconds);
        void audio.play();
      },
      pause: () => audioRef.current?.pause(),
    }),
    []
  );
  const driver = (): ClipMediaController | null =>
    driverRef.current === "page" ? mediaRef.current : audioController;


  // Polls every frame while mounted: the YouTube player has no timeupdate
  // events, and the work per frame is one binary search.
  useEffect(() => {
    let frame = 0;
    const tick = () => {
      frame = requestAnimationFrame(tick);
      const page = mediaRef.current;
      // The page player was started: it drives, and the clip audio stops.
      // (Grace period: pausing YouTube after the audio starts is async.)
      if (page && !page.paused() && driverRef.current === "audio") {
        if (performance.now() - audioStartedAtRef.current > 600) {
          driverRef.current = "page";
          audioRef.current?.pause();
        }
      }
      const media = driverRef.current === "page" ? page : audioController;
      if (!media) return;
      const t = media.currentTime();
      if (stopAtRef.current !== null && t >= stopAtRef.current) {
        stopAtRef.current = null;
        media.pause();
      }
      // Last token that has started; hold it until the next one starts.
      let lo = 0;
      let hi = timeline.length - 1;
      let found = -1;
      while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        if (timeline[mid].start <= t) {
          found = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      const next = found >= 0 && t < timeline[found].end + 0.3 ? timeline[found].key : null;
      setActive((prev) => (prev === next ? prev : next));
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [timeline, mediaRef, audioController]);

  // Space toggles play/pause anywhere on the page except in text fields.
  // Without this, Space re-clicks the focused ▶/token button and restarts.
  useEffect(() => {
    const isTyping = (target: EventTarget | null) =>
      target instanceof HTMLElement &&
      (target.isContentEditable ||
        target.tagName === "TEXTAREA" ||
        target.tagName === "SELECT" ||
        (target.tagName === "INPUT" &&
          !["button", "checkbox", "radio", "range", "submit"].includes(
            (target as HTMLInputElement).type
          )));
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.code !== "Space" || event.repeat || isTyping(event.target)) return;
      const media = driverRef.current === "page" ? mediaRef.current : audioController;
      if (!media) return;
      event.preventDefault();
      event.stopPropagation();
      if (media.paused()) media.play();
      else media.pause();
    };
    // Buttons fire their click on Space keyup; swallow it so the focused
    // button doesn't also restart playback.
    const onKeyUp = (event: KeyboardEvent) => {
      if (event.code === "Space" && !isTyping(event.target)) event.preventDefault();
    };
    window.addEventListener("keydown", onKeyDown, true);
    window.addEventListener("keyup", onKeyUp, true);
    return () => {
      window.removeEventListener("keydown", onKeyDown, true);
      window.removeEventListener("keyup", onKeyUp, true);
    };
  }, [mediaRef, audioController]);

  /** Plays from `clipSeconds` on the current driver; with `stopAt`, pauses there (one line). */
  const playFrom = (clipSeconds: number, stopAt?: number) => {
    const media = driver();
    if (!media) return;
    stopAtRef.current = stopAt ?? null;
    media.play(Math.max(0, clipSeconds));
  };

  const tokenCount = draft.sentences.reduce((n, s) => n + (s.tokens?.length ?? 0), 0);
  const fallbackCount = draft.sentences.reduce(
    (n, s) => n + (s.tokens ?? []).filter((t) => t.readingFallback).length,
    0
  );

  return (
    <EditorSection
      id="review"
      title="Review"
      summary={`${tokenCount} tokens${fallbackCount > 0 ? ` · ${fallbackCount} reading fallbacks` : ""}`}
      actions={
        <>
          <span className="text-xs text-muted-foreground">
            {tokenCount} tokens
            {fallbackCount > 0 ? ` · ${fallbackCount} reading fallbacks` : ""}
          </span>
          <Button
            type="button"
            size="sm"
            variant={editing ? "default" : "outline"}
            disabled={disabled && !editing}
            onClick={() => {
              setEditing((on) => !on);
            }}
          >
            {saving ? <Loader2Icon className="animate-spin" /> : <ScissorsIcon />}
            {editing ? "Done editing" : "Edit tokens"}
          </Button>
        </>
      }
      stickyContent={
        <div className="flex flex-wrap items-center gap-2">
          <audio
            ref={audioRef}
            src={audioUrl}
            controls
            preload="auto"
            className="h-9 min-w-0 flex-1"
            onPlay={(event) => {
              event.currentTarget.playbackRate = rate;
              driverRef.current = "audio";
              audioStartedAtRef.current = performance.now();
              mediaRef.current?.pause();
            }}
          />
          <div className="flex items-center gap-0.5 text-xs" role="group" aria-label="Playback speed">
            {[0.5, 0.75, 1].map((speed) => (
              <button
                key={speed}
                type="button"
                onClick={() => {
                  setRate(speed);
                  if (audioRef.current) audioRef.current.playbackRate = speed;
                }}
                className={cn(
                  "rounded-md px-1.5 py-0.5 tabular-nums transition-colors",
                  rate === speed
                    ? "bg-primary text-primary-foreground"
                    : "text-muted-foreground hover:bg-muted hover:text-foreground"
                )}
              >
                {speed}×
              </button>
            ))}
          </div>
        </div>
      }
    >
      <p className="text-xs text-muted-foreground">
        {editing
          ? "Click a token to split it, merge it with the next one, or fix its reading."
          : "Click a token to play from it. Right-click a token (or turn on Edit tokens) to split, merge or fix its reading."}{" "}
        Split tokens have no timing until you align edited lines; merges keep theirs. Tokens
        follow whichever player you started last: the clip audio above or the video on the
        right.
      </p>
      <ClipTokenLines
        draft={draft}
        active={active}
        editing={editing}
        disabled={disabled}
        saving={saving}
        onPlay={playFrom}
        onEditTokens={(sentence, tokens) => {
          setSaving(true);
          void onEditTokens(sentence, tokens).finally(() => setSaving(false));
        }}
        onClearFlags={(sentence, cleared) => void onClearFlags(sentence, cleared)}
      />
    </EditorSection>
  );
}

/** Lets the trigger show the label rather than the raw model id. */
const SELECT_ITEMS = CLIP_STEP_MODELS.map((model) => ({ value: model.id, label: model.label }));

function ModelPicker({
  label,
  value,
  disabled,
  onChange,
}: {
  label: string;
  value: string;
  disabled?: boolean;
  onChange: (model: string) => void;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <Label>{label}</Label>
      <Select
        items={SELECT_ITEMS}
        value={value}
        disabled={disabled}
        onValueChange={(next) => {
          if (typeof next === "string" && next) onChange(next);
        }}
      >
        <SelectTrigger className="w-52">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {CLIP_STEP_MODELS.map((model) => (
            <SelectItem key={model.id} value={model.id}>
              {model.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}
