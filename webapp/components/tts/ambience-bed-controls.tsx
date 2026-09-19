"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { ChevronLeft, ChevronRight, Pause, Play, Shuffle, Upload } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { dialogueApi, type DialogueScenario } from "@/lib/dialogue/client";
import { ttsApi, type Variant } from "@/lib/tts/client";
import {
  AMBIENCE_KIND_LABELS,
  AMBIENCE_KINDS,
  AMBIENCE_OFFSET_STEP_SECONDS,
  DEFAULT_AMBIENCE_GAIN_DB,
  MAX_AMBIENCE_GAIN_DB,
  MIN_AMBIENCE_GAIN_DB,
  STUDIO_PAUSE_TAKE_AUDIO,
  STUDIO_STOP_AMBIENCE_PREVIEW,
  formatAmbienceSeconds,
  gainDbToLinear,
  randomAmbienceOffset,
  wrapAmbienceOffset,
} from "@/lib/tts/ambience";

const NONE = "Off (dry dialogue)";

export function AmbienceBedControls({
  collectionId,
  scenarioSlug,
  scenario,
  ambienceMixHash,
  selectedVariant,
  projectId,
}: {
  collectionId: string;
  scenarioSlug: string;
  scenario: DialogueScenario;
  ambienceMixHash: string | null;
  selectedVariant: Variant | null;
  projectId: string | undefined;
}) {
  const queryClient = useQueryClient();
  const { data } = useQuery({
    queryKey: ["ambience-assets"],
    queryFn: () => ttsApi.listAmbience(),
  });
  const assets = data?.assets ?? [];
  const selected = assets.find((asset) => asset.id === scenario.ambienceAssetId) ?? null;
  const serverGain = scenario.ambienceGainDb ?? DEFAULT_AMBIENCE_GAIN_DB;
  const serverOffset = selected
    ? wrapAmbienceOffset(scenario.ambienceOffsetSeconds ?? 0, selected.durationSeconds)
    : 0;

  const [playing, setPlaying] = useState(false);
  const [gainDb, setGainDb] = useState(serverGain);
  const [offsetSeconds, setOffsetSeconds] = useState(serverOffset);
  const dialogueRef = useRef<HTMLAudioElement | null>(null);
  const bedRef = useRef<HTMLAudioElement | null>(null);
  const blobUrlsRef = useRef<string[]>([]);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const dirtyRef = useRef(false);
  const persistTimerRef = useRef<number>(0);

  useEffect(() => {
    if (dirtyRef.current) return;
    setGainDb(serverGain);
    setOffsetSeconds(serverOffset);
  }, [scenario.ambienceAssetId, serverGain, serverOffset]);

  useEffect(() => {
    function onStopPreview() {
      stopPreview();
    }
    window.addEventListener(STUDIO_STOP_AMBIENCE_PREVIEW, onStopPreview);
    return () => {
      window.removeEventListener(STUDIO_STOP_AMBIENCE_PREVIEW, onStopPreview);
      window.clearTimeout(persistTimerRef.current);
      stopPreview();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const saveMutation = useMutation({
    mutationFn: (body: {
      assetId: string | null;
      gainDb?: number | null;
      offsetSeconds?: number | null;
    }) => dialogueApi.updateScenarioAmbience(collectionId, scenarioSlug, body),
    onSuccess: () => {
      dirtyRef.current = false;
      queryClient.invalidateQueries({
        queryKey: ["dialogue-scenario", collectionId, scenarioSlug],
      });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-collection-audio-status", collectionId],
      });
    },
    onError: (error) => toast.error(error.message),
  });

  const uploadMutation = useMutation({
    mutationFn: async (file: File) => {
      const title = file.name.replace(/\.[^.]+$/, "") || "Ambience";
      const { asset } = await ttsApi.uploadAmbience({
        file,
        title,
        kind: "other",
      });
      await dialogueApi.updateScenarioAmbience(collectionId, scenarioSlug, {
        assetId: asset.id,
        gainDb: scenario.ambienceGainDb ?? DEFAULT_AMBIENCE_GAIN_DB,
        offsetSeconds: randomAmbienceOffset(asset.durationSeconds),
      });
      return asset;
    },
    onSuccess: (asset) => {
      stopPreview();
      queryClient.invalidateQueries({ queryKey: ["ambience-assets"] });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-scenario", collectionId, scenarioSlug],
      });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-collection-audio-status", collectionId],
      });
      toast.success(`Attached “${asset.title}” under this scene.`);
    },
    onError: (error) => toast.error(error.message),
  });

  const mixStale =
    !!scenario.publishedAudioUrl &&
    (scenario.publishedAmbienceHash ?? null) !== (ambienceMixHash ?? null);

  function stopPreview() {
    dialogueRef.current?.pause();
    bedRef.current?.pause();
    dialogueRef.current = null;
    bedRef.current = null;
    for (const url of blobUrlsRef.current) URL.revokeObjectURL(url);
    blobUrlsRef.current = [];
    setPlaying(false);
  }

  function persistMix(nextGain: number, nextOffset: number) {
    if (!selected) return;
    window.clearTimeout(persistTimerRef.current);
    persistTimerRef.current = window.setTimeout(() => {
      saveMutation.mutate({
        assetId: selected.id,
        gainDb: nextGain,
        offsetSeconds: nextOffset,
      });
    }, 400);
  }

  async function fetchBlobUrl(url: string, mime: string): Promise<string> {
    const res = await fetch(url);
    if (!res.ok) throw new Error("Could not load audio for preview.");
    const buffer = await res.arrayBuffer();
    const objectUrl = URL.createObjectURL(new Blob([buffer], { type: mime }));
    blobUrlsRef.current.push(objectUrl);
    return objectUrl;
  }

  async function togglePreview() {
    if (playing) {
      stopPreview();
      return;
    }
    if (!selectedVariant || !projectId || !selected) return;
    try {
      window.dispatchEvent(new Event(STUDIO_PAUSE_TAKE_AUDIO));
      const [dialogueUrl, bedUrl] = await Promise.all([
        fetchBlobUrl(
          ttsApi.variantAudioUrl(projectId, selectedVariant.id, selectedVariant.audioByteCount),
          "audio/wav"
        ),
        fetchBlobUrl(ttsApi.ambienceAudioUrl(selected.id), selected.contentType),
      ]);
      const dialogue = new Audio(dialogueUrl);
      const bed = new Audio(bedUrl);
      dialogueRef.current = dialogue;
      bedRef.current = bed;
      bed.loop = true;
      bed.volume = gainDbToLinear(gainDb);
      try {
        bed.currentTime = offsetSeconds;
      } catch {
        /* some codecs reject a seek before metadata */
        bed.onloadedmetadata = () => {
          bed.currentTime = offsetSeconds;
        };
      }
      dialogue.onended = () => stopPreview();
      await Promise.all([dialogue.play(), bed.play()]);
      setPlaying(true);
    } catch (error) {
      stopPreview();
      toast.error(error instanceof Error ? error.message : "Preview failed.");
    }
  }

  function onSelectAsset(assetId: string | null) {
    stopPreview();
    dirtyRef.current = false;
    if (!assetId) {
      saveMutation.mutate({ assetId: null });
      return;
    }
    const asset = assets.find((item) => item.id === assetId);
    saveMutation.mutate({
      assetId,
      gainDb: DEFAULT_AMBIENCE_GAIN_DB,
      offsetSeconds: randomAmbienceOffset(asset?.durationSeconds ?? 0),
    });
  }

  function onGain(next: number) {
    dirtyRef.current = true;
    setGainDb(next);
    if (bedRef.current) bedRef.current.volume = gainDbToLinear(next);
    persistMix(next, offsetSeconds);
  }

  function onOffset(next: number) {
    if (!selected) return;
    const wrapped = wrapAmbienceOffset(next, selected.durationSeconds);
    dirtyRef.current = true;
    setOffsetSeconds(wrapped);
    if (bedRef.current) {
      try {
        bedRef.current.currentTime = wrapped;
      } catch {
        /* ignore */
      }
    }
    persistMix(gainDb, wrapped);
  }

  const grouped = AMBIENCE_KINDS.map((kind) => ({
    kind,
    assets: assets.filter((asset) => asset.kind === kind),
  })).filter((group) => group.assets.length > 0);

  return (
    <div className="flex flex-col gap-3 rounded-md border p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-medium">Background ambience</h3>
        <Link
          href="/tts/ambience"
          className="text-xs text-muted-foreground hover:text-foreground"
        >
          Manage library
        </Link>
      </div>
      <p className="text-sm text-muted-foreground">
        Optional loop mixed under the published clip (street, cafe, ocean, …).
        Short files loop to the take length. Waveform and karaoke stay on the
        dry dialogue.
      </p>

      {assets.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          Nothing in the library yet. Upload a loop to attach it to this scene.
        </p>
      ) : null}

      <div className="flex flex-wrap items-end gap-3">
        <div className="flex min-w-56 flex-1 flex-col gap-2">
          <Label>Ambience</Label>
          <Select
            value={selected?.id ?? NONE}
            onValueChange={(value) =>
              onSelectAsset(!value || value === NONE ? null : value)
            }
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Off (dry dialogue)" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={NONE}>Off (dry dialogue)</SelectItem>
              {grouped.map((group) => (
                <SelectGroup key={group.kind}>
                  <SelectLabel>{AMBIENCE_KIND_LABELS[group.kind]}</SelectLabel>
                  {group.assets.map((asset) => (
                    <SelectItem key={asset.id} value={asset.id}>
                      {asset.title}
                    </SelectItem>
                  ))}
                </SelectGroup>
              ))}
            </SelectContent>
          </Select>
        </div>
        <input
          ref={fileInputRef}
          type="file"
          accept="audio/wav,audio/wave,audio/x-wav,audio/mpeg,audio/mp3,audio/mp4,audio/m4a,audio/x-m4a,.wav,.mp3,.m4a"
          className="sr-only"
          onChange={(event) => {
            const file = event.target.files?.[0];
            event.target.value = "";
            if (file) uploadMutation.mutate(file);
          }}
        />
        <Button
          type="button"
          variant={assets.length === 0 ? "default" : "outline"}
          disabled={uploadMutation.isPending}
          onClick={() => fileInputRef.current?.click()}
        >
          <Upload className="mr-1 size-3.5" />
          {uploadMutation.isPending
            ? "Uploading…"
            : selected
              ? "Replace file"
              : "Upload & attach"}
        </Button>
      </div>

      {selected ? (
        <>
          <div className="flex max-w-xl flex-col gap-2">
            <Label htmlFor="ambience-gain">
              Ambience volume {gainDb.toFixed(0)} dB
            </Label>
            <input
              id="ambience-gain"
              type="range"
              min={MIN_AMBIENCE_GAIN_DB}
              max={MAX_AMBIENCE_GAIN_DB}
              step={1}
              value={gainDb}
              onChange={(event) => onGain(Number(event.target.value))}
              className="h-2 w-full cursor-pointer appearance-none rounded-full bg-muted accent-primary"
            />
            <p className="text-xs text-muted-foreground">
              Quieter ← → louder (default −22 dB, under the dialogue)
            </p>
          </div>

          <div className="flex max-w-xl flex-col gap-2">
            <Label htmlFor="ambience-offset">
              Loop start {formatAmbienceSeconds(offsetSeconds)} / {formatAmbienceSeconds(selected.durationSeconds)}
            </Label>
            <input
              id="ambience-offset"
              type="range"
              min={0}
              max={Math.max(0.1, selected.durationSeconds)}
              step={0.1}
              value={Math.min(offsetSeconds, selected.durationSeconds)}
              onChange={(event) => onOffset(Number(event.target.value))}
              className="h-2 w-full cursor-pointer appearance-none rounded-full bg-muted accent-primary"
            />
            <div className="flex flex-wrap items-center gap-2">
              <Button
                type="button"
                variant="outline"
                size="icon-sm"
                aria-label="Nudge start earlier"
                onClick={() => onOffset(offsetSeconds - AMBIENCE_OFFSET_STEP_SECONDS)}
              >
                <ChevronLeft />
              </Button>
              <Button
                type="button"
                variant="outline"
                size="icon-sm"
                aria-label="Nudge start later"
                onClick={() => onOffset(offsetSeconds + AMBIENCE_OFFSET_STEP_SECONDS)}
              >
                <ChevronRight />
              </Button>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => onOffset(randomAmbienceOffset(selected.durationSeconds))}
              >
                <Shuffle className="mr-1" />
                Randomize
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">
              Drag to pick where in the loop this scene starts.
            </p>
          </div>

          <div>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={!selectedVariant || !projectId}
              onClick={() => void togglePreview()}
            >
              {playing ? (
                <>
                  <Pause className="mr-1" />
                  Stop preview
                </>
              ) : (
                <>
                  <Play className="mr-1" />
                  Preview mix
                </>
              )}
            </Button>
            {!selectedVariant ? (
              <p className="mt-2 text-xs text-muted-foreground">
                Select a take to preview dialogue with this ambience.
              </p>
            ) : (
              <p className="mt-2 text-xs text-muted-foreground">
                Pauses the waveform so you hear one dialogue track plus the loop.
              </p>
            )}
          </div>
        </>
      ) : null}

      {mixStale ? (
        <p className="text-xs text-amber-600 dark:text-amber-400">
          Bed, level, or loop start changed since the last publish — republish
          to update the learner clip.
        </p>
      ) : null}
    </div>
  );
}
