"use client";

import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { ExternalLink, TriangleAlert } from "lucide-react";
import { Button, buttonVariants } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";
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
    mutationFn: async () => {
      await onSaveScenario();
      const ensured = await dialogueApi.ensureScenarioAudio(
        collectionId,
        scenarioSlug,
        { speaker1Voice, speaker2Voice }
      );
      if (!ensured.project) {
        throw new Error("Failed to prepare the audio track.");
      }
      await ttsApi.generate(ensured.project.id);
      return ensured.project.id;
    },
    onSuccess: (projectId) => {
      invalidateAudioQueries(projectId);
      toast.success("New take generated.");
    },
    onError: (error) => toast.error(error.message),
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

  return (
    <div className="flex max-w-5xl flex-col gap-6">
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
                onClick={() => generateMutation.mutate()}
                disabled={generateMutation.isPending}
              >
                {generateMutation.isPending ? "Regenerating…" : "Regenerate"}
              </Button>
            </div>
          )}

          <div className="flex flex-wrap items-center gap-3">
            <Button
              onClick={() => generateMutation.mutate()}
              disabled={generateMutation.isPending}
            >
              {generateMutation.isPending ? "Generating…" : "Generate take"}
            </Button>
            {hasUnsavedChanges && (
              <p className="text-sm text-muted-foreground">
                Unsaved line edits will be saved before generating.
              </p>
            )}
          </div>

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

      {project && (
        <VariantList
          projectId={project.id}
          dialogueLines={editorLines}
          currentContentHash={data.currentContentHash}
          selectedVariantId={selectedVariant}
          hasUnsavedChanges={hasUnsavedChanges}
        />
      )}
    </div>
  );
}
