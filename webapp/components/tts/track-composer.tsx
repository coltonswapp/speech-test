"use client";

import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Skeleton } from "@/components/ui/skeleton";
import { ttsApi } from "@/lib/tts/client";
import { OPENAI_DEFAULT_MODEL } from "@/lib/tts/voices";
import { GEMINI_TTS_DEFAULT_MODEL } from "@/lib/tts/gemini-voices";
import { VariantList } from "@/components/tts/variant-list";
import { VoiceSelect } from "@/components/tts/voice-select";
import {
  DialogueLineEditor,
  type EditableDialogueLine,
} from "@/components/tts/dialogue-line-editor";

type CompositionMode = "narration" | "conversation";

export function TrackComposer({ projectId }: { projectId: string }) {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["tts-project", projectId],
    queryFn: () => ttsApi.getProject(projectId),
  });

  const [trackName, setTrackName] = useState("");
  const [compositionMode, setCompositionMode] =
    useState<CompositionMode>("narration");

  // Narration fields
  const [promptText, setPromptText] = useState("");
  const [instructions, setInstructions] = useState("");
  const [voice, setVoice] = useState<string>("coral");

  // Conversation fields
  const [speaker1Name, setSpeaker1Name] = useState("");
  const [speaker2Name, setSpeaker2Name] = useState("");
  const [speaker1Voice, setSpeaker1Voice] = useState<string>("Zephyr");
  const [speaker2Voice, setSpeaker2Voice] = useState<string>("Puck");
  const [dialogueLines, setDialogueLines] = useState<EditableDialogueLine[]>(
    []
  );

  useEffect(() => {
    if (data?.project) {
      setTrackName(data.project.trackName ?? "");
      setCompositionMode(
        (data.project.compositionMode as CompositionMode) ?? "narration"
      );
      setPromptText(data.project.promptText);
      setInstructions(data.project.instructions ?? "");
      setVoice(data.project.voice);
      setSpeaker1Name(data.project.speaker1Name ?? "");
      setSpeaker2Name(data.project.speaker2Name ?? "");
      setSpeaker1Voice(data.project.speaker1Voice ?? "Zephyr");
      setSpeaker2Voice(data.project.speaker2Voice ?? "Puck");
      setDialogueLines(
        data.dialogueLines.length > 0
          ? data.dialogueLines.map((l) => ({
              id: l.id,
              speaker: l.speaker,
              text: l.text,
            }))
          : [{ id: crypto.randomUUID(), speaker: "speaker1", text: "" }]
      );
    }
  }, [data]);

  const saveMutation = useMutation({
    mutationFn: () => {
      // Scenario-backed tracks: text lives on the scenario, so only persist
      // presentation fields — never promptText or line copies.
      if (data?.project.sourceScenarioId) {
        return ttsApi.updateProject(projectId, {
          trackName: trackName.trim() || null,
          speaker1Voice,
          speaker2Voice,
        });
      }
      return ttsApi.updateProject(projectId, {
        trackName: trackName.trim() || null,
        compositionMode,
        promptText,
        instructions: instructions.trim() || null,
        voice,
        provider: compositionMode === "conversation" ? "gemini" : "openai",
        model:
          compositionMode === "conversation"
            ? GEMINI_TTS_DEFAULT_MODEL
            : OPENAI_DEFAULT_MODEL,
        speaker1Name: speaker1Name.trim() || null,
        speaker2Name: speaker2Name.trim() || null,
        speaker1Voice,
        speaker2Voice,
        dialogueLines:
          compositionMode === "conversation"
            ? dialogueLines
                .filter((l) => l.text.trim().length > 0)
                .map((l) => ({ speaker: l.speaker, text: l.text }))
            : undefined,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-project", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      toast.success("Track saved.");
    },
    onError: (error) => toast.error(error.message),
  });

  const generateMutation = useMutation({
    mutationFn: async () => {
      await saveMutation.mutateAsync();
      return ttsApi.generate(projectId);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      toast.success("New take generated.");
    },
    onError: (error) => toast.error(error.message),
  });

  if (isLoading || !data) {
    return (
      <div className="flex flex-1 flex-col gap-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  // Scenario-backed tracks speak the scenario's lines at generation time —
  // text is edited in Content Studio, only voices/takes are managed here.
  const sourceScenarioId = data.project.sourceScenarioId;
  // Scenario ids are "<collectionId>/<slug>", matching the editor's URL shape.
  const scenarioHref = sourceScenarioId
    ? `/content/dialogues/${sourceScenarioId}?tab=audio`
    : null;

  const canGenerate = sourceScenarioId
    ? true
    : compositionMode === "conversation"
      ? dialogueLines.some((l) => l.text.trim().length > 0)
      : promptText.trim().length > 0;

  return (
    <div className="flex min-w-0 flex-1 flex-col gap-6">
      {sourceScenarioId && (
        <div className="flex flex-col gap-2 rounded-md border bg-muted/50 px-3 py-2 text-sm sm:flex-row sm:items-center sm:justify-between sm:gap-3">
          <span className="text-muted-foreground">
            This track is backed by the scenario{" "}
            <span className="font-medium text-foreground">
              {sourceScenarioId}
            </span>
            {" — "}its dialogue is managed in Content Studio.
          </span>
          <a
            href={scenarioHref!}
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            Open scenario
          </a>
        </div>
      )}

      <div className="flex flex-col gap-2">
        <Label htmlFor="trackName">Track name</Label>
        <Input
          id="trackName"
          value={trackName}
          onChange={(e) => setTrackName(e.target.value)}
          placeholder="Untitled track"
        />
      </div>

      {!sourceScenarioId && (
        <Tabs
          value={compositionMode}
          onValueChange={(value) => {
            if (value) setCompositionMode(value as CompositionMode);
          }}
        >
          <TabsList>
            <TabsTrigger value="narration">Narration</TabsTrigger>
            <TabsTrigger value="conversation">Conversation</TabsTrigger>
          </TabsList>
        </Tabs>
      )}

      {sourceScenarioId ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div className="flex flex-col gap-2">
            <Label>Voice for {speaker1Name || "Speaker 1"}</Label>
            <VoiceSelect
              provider="gemini"
              value={speaker1Voice}
              onChange={setSpeaker1Voice}
            />
          </div>
          <div className="flex flex-col gap-2">
            <Label>Voice for {speaker2Name || "Speaker 2"}</Label>
            <VoiceSelect
              provider="gemini"
              value={speaker2Voice}
              onChange={setSpeaker2Voice}
            />
          </div>
        </div>
      ) : compositionMode === "narration" ? (
        <>
          <div className="flex flex-col gap-2">
            <Label htmlFor="promptText">Composition</Label>
            <Textarea
              id="promptText"
              rows={6}
              value={promptText}
              onChange={(e) => setPromptText(e.target.value)}
              placeholder="Type the narration text here…"
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="instructions">Instructions (optional)</Label>
            <Textarea
              id="instructions"
              rows={2}
              value={instructions}
              onChange={(e) => setInstructions(e.target.value)}
              placeholder="e.g. speak slowly, warm tone"
            />
          </div>

          <div className="flex items-end gap-4">
            <div className="flex flex-col gap-2">
              <Label>Voice</Label>
              <VoiceSelect
                provider="openai"
                value={voice}
                onChange={setVoice}
                className="w-48"
              />
            </div>
          </div>
        </>
      ) : (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-2">
              <Label>Speaker 1 name</Label>
              <Input
                value={speaker1Name}
                onChange={(e) => setSpeaker1Name(e.target.value)}
                placeholder="Speaker 1"
              />
              <Label>Speaker 1 voice</Label>
              <VoiceSelect
                provider="gemini"
                value={speaker1Voice}
                onChange={setSpeaker1Voice}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label>Speaker 2 name</Label>
              <Input
                value={speaker2Name}
                onChange={(e) => setSpeaker2Name(e.target.value)}
                placeholder="Speaker 2"
              />
              <Label>Speaker 2 voice</Label>
              <VoiceSelect
                provider="gemini"
                value={speaker2Voice}
                onChange={setSpeaker2Voice}
              />
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <Label>Dialogue</Label>
            <DialogueLineEditor
              lines={dialogueLines}
              onChange={setDialogueLines}
              speaker1Name={speaker1Name}
              speaker2Name={speaker2Name}
            />
          </div>
        </>
      )}

      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-4">
        <Button
          variant="outline"
          className="min-h-11 touch-manipulation sm:min-h-8"
          onClick={() => saveMutation.mutate()}
          disabled={saveMutation.isPending}
        >
          Save
        </Button>
        <Button
          className="min-h-11 touch-manipulation sm:min-h-8"
          onClick={() => generateMutation.mutate()}
          disabled={generateMutation.isPending || !canGenerate}
        >
          {generateMutation.isPending ? "Generating…" : "Generate take"}
        </Button>
      </div>

      <VariantList
        projectId={projectId}
        dialogueLines={
          compositionMode === "conversation" ? dialogueLines : undefined
        }
      />
    </div>
  );
}
