"use client";

import { useEffect, useMemo, useState, useRef, type MouseEvent } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { ChevronDown, ExternalLink, TriangleAlert } from "lucide-react";
import { Button, buttonVariants } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";
import { Card, CardAction, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { dialogueApi } from "@/lib/dialogue/client";
import { ttsApi } from "@/lib/tts/client";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";
import { isSpokenLine, isStageLine, type DialogueLine } from "@/lib/dialogue/types";
import { VariantList } from "@/components/tts/variant-list";
import { VoiceSelect } from "@/components/tts/voice-select";
import type { EditableDialogueLine } from "@/components/tts/dialogue-line-editor";
import { flushPendingTokenSync } from "@/lib/dialogue/token-sync-persist";

// The scenario's audio workspace: voices, take generation, staleness, publish,
// and the shared take list/waveform editor. The scenario's lines are the single
// source of truth — generation always speaks the saved lines.

type TakeCount = 1 | 2 | 3;

export function ScenarioAudioPanel({
  collectionId,
  scenarioSlug,
  lines,
  hasUnsavedChanges,
  onSaveScenario,
}: {
  collectionId: string;
  scenarioSlug: string;
  lines: DialogueLine[];
  hasUnsavedChanges: boolean;
  onSaveScenario: () => Promise<unknown>;
}) {
  const queryClient = useQueryClient();
  const scenarioId = `${collectionId}/${scenarioSlug}`;

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["scenario-audio", scenarioId],
    queryFn: () => dialogueApi.getScenarioAudio(collectionId, scenarioSlug),
  });

  const scenarioQuery = useQuery({
    queryKey: ["dialogue-scenario", collectionId, scenarioSlug],
    queryFn: () => dialogueApi.getScenario(collectionId, scenarioSlug),
  });

  const conversation = useMemo(
    () => scenarioLinesToConversation(lines),
    [lines]
  );

  const [speaker1Voice, setSpeaker1Voice] = useState("Zephyr");
  const [speaker2Voice, setSpeaker2Voice] = useState("Puck");
  const [generateProgress, setGenerateProgress] = useState<{
    current: number;
    total: number;
  } | null>(null);

  useEffect(() => {
    if (!data) return;
    setSpeaker1Voice(data.project?.speaker1Voice ?? "Zephyr");
    setSpeaker2Voice(data.project?.speaker2Voice ?? "Puck");
  }, [data]);

  const invalidateAudioQueries = (projectId?: string) => {
    if (projectId) {
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
    }
    queryClient.invalidateQueries({ queryKey: ["scenario-audio", scenarioId] });
    queryClient.invalidateQueries({
      queryKey: ["dialogue-scenario", collectionId, scenarioSlug],
    });
    queryClient.invalidateQueries({
      queryKey: ["dialogue-collection-audio-status", collectionId],
    });
    queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
  };

  const generateMutation = useMutation({
    mutationFn: async (count: TakeCount) => {
      await onSaveScenario();
      const ensured = await dialogueApi.ensureScenarioAudio(
        collectionId,
        scenarioSlug,
        { speaker1Voice, speaker2Voice }
      );
      if (!ensured.project) {
        throw new Error("Failed to prepare the audio track.");
      }
      const projectId = ensured.project.id;
      let succeeded = 0;
      let lastError: Error | null = null;
      const toastId = "generate-takes";
      for (let i = 0; i < count; i++) {
        setGenerateProgress({ current: i + 1, total: count });
        if (count > 1) {
          toast.loading(`Generating ${i + 1}/${count}…`, { id: toastId });
        }
        try {
          // Separate calls so Gemini can produce variety across takes.
          await ttsApi.generate(projectId);
          succeeded += 1;
        } catch (error) {
          lastError =
            error instanceof Error ? error : new Error(String(error));
          break;
        }
      }
      return { projectId, succeeded, total: count, lastError, toastId };
    },
    onSuccess: ({ projectId, succeeded, total, lastError, toastId }) => {
      invalidateAudioQueries(projectId);
      setGenerateProgress(null);
      if (succeeded === 0) {
        toast.error(lastError?.message ?? "Failed to generate take.", {
          id: toastId,
        });
        return;
      }
      if (lastError) {
        toast.warning(
          `Generated ${succeeded} of ${total} takes. ${lastError.message}`,
          { id: toastId }
        );
        return;
      }
      if (total === 1) {
        toast.success("New take generated.", { id: toastId });
        return;
      }
      toast.success(`Generated ${succeeded} takes.`, { id: toastId });
    },
    onError: (error) => {
      setGenerateProgress(null);
      toast.error(error.message, { id: "generate-takes" });
    },
  });

  const publishMutation = useMutation({
    mutationFn: async () => {
      await onSaveScenario();
      await flushPendingTokenSync();
      return dialogueApi.publishScenario(collectionId, scenarioSlug);
    },
    onSuccess: (result) => {
      invalidateAudioQueries(data?.project?.id);
      toast.success(
        result.hasTokenKaraoke
          ? "Audio published with token karaoke."
          : "Audio published to the learner CDN."
      );
    },
    onError: (error) => toast.error(error.message),
  });

  const unpublishMutation = useMutation({
    mutationFn: () => dialogueApi.unpublishScenario(collectionId, scenarioSlug),
    onSuccess: () => {
      invalidateAudioQueries(data?.project?.id);
      toast.success("Published audio removed.");
    },
    onError: (error) => toast.error(error.message),
  });

  const projectId = data?.project?.id;
  const variantsQuery = useQuery({
    queryKey: ["tts-variants", projectId],
    queryFn: () => ttsApi.listVariants(projectId!),
    enabled: !!projectId,
  });

  if (isLoading) {
    return (
      <div className="flex flex-col gap-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="flex flex-col gap-2 text-sm text-muted-foreground">
        {error instanceof Error ? error.message : "Failed to load scenario audio."}
      </div>
    );
  }

  const project = data.project;
  const scenario = scenarioQuery.data?.scenario;
  const speakableLineCount = conversation.lines.length;
  const selectedVariant = project?.selectedVariantId ?? null;
  const selectedVariantHash = variantsQuery.data?.variants.find(
    (v) => v.id === selectedVariant
  )?.contentHash;
  const selectedTakeIsStale =
    !!selectedVariantHash && selectedVariantHash !== data.currentContentHash;
  const publishedAudioUrl = scenario?.publishedAudioUrl ?? null;
  const publishStale =
    !!publishedAudioUrl &&
    !!scenario?.publishedContentHash &&
    scenario.publishedContentHash !== data.currentContentHash;
  const canPublish = !!selectedVariant && !hasUnsavedChanges;

  const editorLines: EditableDialogueLine[] = (() => {
    const out: EditableDialogueLine[] = [];
    let spokenI = 0;
    lines.forEach((line, index) => {
      if (isStageLine(line)) {
        if (line.visibility === "cold" && line.text.trim()) {
          out.push({
            id: `stage-${index}`,
            speaker: "speaker1",
            text: line.text.trim(),
            kind: "stage",
          });
        }
        return;
      }
      if (!isSpokenLine(line)) return;
      const spoken = conversation.lines[spokenI];
      spokenI += 1;
      if (!spoken) return;
      out.push({
        id: String(index),
        speaker: spoken.speaker,
        text: spoken.text,
        kind: "spoken",
      });
    });
    return out;
  })();

  const speaker1Label = conversation.speaker1Name ?? "Speaker 1";
  const speaker2Label = conversation.speaker2Name ?? "Speaker 2";
  const generateBusy = generateMutation.isPending;
  const generateLabel = generateBusy
    ? generateProgress && generateProgress.total > 1
      ? `Generating ${generateProgress.current}/${generateProgress.total}…`
      : "Generating…"
    : "Generate take";

  return (
    <div className="flex w-full min-w-0 flex-col gap-6">
      {speakableLineCount === 0 ? (
        <p className="text-sm text-muted-foreground">
          Add dialogue lines with a speaker and Japanese text first — audio is
          generated from the scenario&apos;s lines.
        </p>
      ) : (
        <>
          {conversation.speakerNames.length > 2 && (
            <p className="flex items-center gap-2 text-sm text-amber-600 dark:text-amber-400">
              <TriangleAlert className="size-4" />
              This scenario has {conversation.speakerNames.length} speakers, but
              synthesis supports two voices — extra speakers alternate between
              them.
            </p>
          )}

          {(data.castVoices?.length ?? 0) > 0 && (
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-xs text-muted-foreground">
                Collection cast:
              </span>
              {data.castVoices?.map((entry) => (
                <Badge key={`${entry.name}:${entry.voice}`} variant="secondary">
                  {entry.name} → {entry.voice}
                </Badge>
              ))}
            </div>
          )}

          <div className="grid max-w-2xl grid-cols-2 gap-4">
            <div className="flex flex-col gap-2">
              <Label>Voice for {speaker1Label}</Label>
              <VoiceSelect
                provider="gemini"
                value={speaker1Voice}
                onChange={setSpeaker1Voice}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label>Voice for {speaker2Label}</Label>
              <VoiceSelect
                provider="gemini"
                value={speaker2Voice}
                onChange={setSpeaker2Voice}
              />
            </div>
          </div>

          {selectedTakeIsStale && !hasUnsavedChanges && (
            <div className="flex items-center gap-3 rounded-md border border-amber-500/50 bg-amber-500/10 px-3 py-2 text-sm text-amber-700 dark:text-amber-300">
              <TriangleAlert className="size-4 shrink-0" />
              <span>
                The dialogue text changed since the selected take was
                generated.
              </span>
              <Button
                variant="outline"
                size="sm"
                onClick={() => generateMutation.mutate(1)}
                disabled={generateBusy}
              >
                {generateBusy ? "Regenerating…" : "Regenerate"}
              </Button>
            </div>
          )}

            <div className="flex flex-col gap-3 rounded-md border p-4">
            <div className="flex flex-wrap items-center gap-2">
              <h3 className="text-sm font-medium">Publish scenario audio</h3>
              {publishedAudioUrl ? (
                publishStale ? (
                  <Badge
                    variant="outline"
                    className="border-amber-500/50 text-amber-600 dark:text-amber-400"
                  >
                    published · stale
                  </Badge>
                ) : (
                  <Badge variant="secondary">published</Badge>
                )
              ) : (
                <Badge variant="outline">unpublished</Badge>
              )}
            </div>
            <p className="text-sm text-muted-foreground">
              Encodes this scenario&apos;s selected take as m4a and uploads it to
              the public CDN. Prefer <span className="font-medium">Publish lesson</span>{" "}
              on the collection page to ship the full lesson JSON with every
              scenario&apos;s URL; use this to republish one scenario.
            </p>
            <div className="flex flex-wrap items-center gap-3">
              <Button
                onClick={() => publishMutation.mutate()}
                disabled={!canPublish || publishMutation.isPending}
              >
                {publishMutation.isPending
                  ? "Publishing…"
                  : publishedAudioUrl
                    ? "Republish"
                    : "Publish"}
              </Button>
              {publishedAudioUrl && (
                <Button
                  variant="outline"
                  onClick={() => unpublishMutation.mutate()}
                  disabled={unpublishMutation.isPending}
                >
                  {unpublishMutation.isPending ? "Removing…" : "Unpublish"}
                </Button>
              )}
              {publishedAudioUrl && (
                <a
                  href={publishedAudioUrl}
                  target="_blank"
                  rel="noreferrer"
                  className={buttonVariants({ variant: "ghost" })}
                >
                  <ExternalLink className="mr-1 size-3.5" />
                  Open CDN URL
                </a>
              )}
            </div>
            {!selectedVariant && (
              <p className="text-xs text-muted-foreground">
                Select a take below before publishing.
              </p>
            )}
            {publishStale && (
              <p className="text-xs text-amber-600 dark:text-amber-400">
                Dialogue text changed since the last publish — republish to update
                the learner clip.
              </p>
            )}
          </div>
        </>
      )}

      {project ? (
        <VariantList
          projectId={project.id}
          dialogueLines={editorLines}
          currentContentHash={data.currentContentHash}
          selectedVariantId={selectedVariant}
          hasUnsavedChanges={hasUnsavedChanges}
          headerActions={
            <div className="flex flex-wrap items-center gap-2">
              <GenerateTakeControl
                label={generateLabel}
                disabled={generateBusy || speakableLineCount === 0}
                onGenerate={(count) => generateMutation.mutate(count)}
              />
              {hasUnsavedChanges && (
                <span className="text-xs text-muted-foreground">
                  Unsaved line edits will be saved before generating.
                </span>
              )}
            </div>
          }
          emptyHint="No takes yet — use Generate take in this header."
        />
      ) : speakableLineCount > 0 ? (
        <Card>
          <CardHeader>
            <CardTitle className="text-base font-medium">Takes</CardTitle>
            <CardAction>
              <div className="flex flex-wrap items-center justify-end gap-2">
                <GenerateTakeControl
                  label={generateLabel}
                  disabled={generateBusy}
                  onGenerate={(count) => generateMutation.mutate(count)}
                />
                {hasUnsavedChanges && (
                  <span className="text-xs text-muted-foreground">
                    Unsaved line edits will be saved before generating.
                  </span>
                )}
              </div>
            </CardAction>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-muted-foreground">
              No takes yet — use Generate take in this header.
            </p>
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}

function GenerateTakeControl({
  label,
  disabled,
  onGenerate,
}: {
  label: string;
  disabled: boolean;
  onGenerate: (count: TakeCount) => void;
}) {
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null);

  function onContextMenu(event: MouseEvent<HTMLButtonElement>) {
    event.preventDefault();
    event.stopPropagation();
    if (disabled) return;
    setMenu({ x: event.clientX, y: event.clientY });
  }

  return (
    <>
      <div className="inline-flex items-stretch">
        <Button
          size="sm"
          className="rounded-r-none"
          onClick={() => onGenerate(1)}
          onContextMenu={onContextMenu}
          disabled={disabled}
          title="Left-click: 1 take. Right-click: choose 1–3 takes."
        >
          {label}
        </Button>
        <DropdownMenu>
          <DropdownMenuTrigger
            disabled={disabled}
            render={
              <Button
                size="sm"
                className="rounded-l-none border-l border-primary-foreground/20 px-1.5"
                aria-label="Generate multiple takes"
                disabled={disabled}
              >
                <ChevronDown className="size-3.5" />
              </Button>
            }
          />
          <DropdownMenuContent align="end" className="min-w-44">
            <DropdownMenuItem onClick={() => onGenerate(1)}>
              Generate 1 take
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => onGenerate(2)}>
              Generate 2 takes
              <span className="ml-auto text-xs text-muted-foreground">variety</span>
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => onGenerate(3)}>
              Generate 3 takes
              <span className="ml-auto text-xs text-muted-foreground">variety</span>
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      {menu && (
        <GenerateTakeContextMenu
          x={menu.x}
          y={menu.y}
          onChoose={(count) => {
            setMenu(null);
            onGenerate(count);
          }}
          onClose={() => setMenu(null)}
        />
      )}
    </>
  );
}

function GenerateTakeContextMenu({
  x,
  y,
  onChoose,
  onClose,
}: {
  x: number;
  y: number;
  onChoose: (count: TakeCount) => void;
  onClose: () => void;
}) {
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    function onPointer(event: PointerEvent) {
      if (!menuRef.current?.contains(event.target as Node)) {
        onClose();
      }
    }
    window.addEventListener("keydown", onKey);
    window.addEventListener("pointerdown", onPointer, true);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("pointerdown", onPointer, true);
    };
  }, [onClose]);

  const left = Math.min(x, typeof window !== "undefined" ? window.innerWidth - 200 : x);
  const top = Math.min(y, typeof window !== "undefined" ? window.innerHeight - 120 : y);

  return (
    <div
      ref={menuRef}
      role="menu"
      className="fixed z-50 min-w-[11rem] rounded-md border bg-popover p-1 text-popover-foreground shadow-md"
      style={{ left, top }}
    >
      {(
        [
          { count: 1 as const, label: "Generate 1 take" },
          { count: 2 as const, label: "Generate 2 takes", hint: "variety" },
          { count: 3 as const, label: "Generate 3 takes", hint: "variety" },
        ] as const
      ).map((item) => (
        <button
          key={item.count}
          type="button"
          role="menuitem"
          className="flex w-full items-center rounded-sm px-2 py-1.5 text-left text-sm hover:bg-accent"
          onClick={() => onChoose(item.count)}
        >
          {item.label}
          {"hint" in item && item.hint ? (
            <span className="ml-auto text-xs text-muted-foreground">{item.hint}</span>
          ) : null}
        </button>
      ))}
    </div>
  );
}
