"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  Check,
  Lock,
  Pause,
  Play,
  Shuffle,
  SlidersHorizontal,
  Trash2,
  Upload,
  WandSparkles,
} from "lucide-react";
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
import {
  dialogueApi,
  formatPublishedAt,
  type DialogueScenario,
} from "@/lib/dialogue/client";
import { flushPendingTokenSync } from "@/lib/dialogue/token-sync-persist";
import { ttsApi, type AmbienceAsset } from "@/lib/tts/client";
import {
  DEFAULT_AMBIENCE_GAIN_DB,
  MAX_AMBIENCE_GAIN_DB,
  MAX_AMBIENCE_LAYERS,
  MIN_AMBIENCE_GAIN_DB,
  STUDIO_PAUSE_TAKE_AUDIO,
  STUDIO_STOP_AMBIENCE_PREVIEW,
  STUDIO_TOGGLE_MARRIED_MIX,
  createAmbienceLayer,
  formatAmbienceSeconds,
  gainDbToLinear,
  groupAmbienceAssets,
  layersFromScenario,
  randomAmbienceOffset,
  wrapAmbienceOffset,
  type AmbienceLayer,
} from "@/lib/tts/ambience";
import { AmbienceKindField } from "@/components/tts/ambience-kind-field";
import { AmbienceLane } from "@/components/tts/ambience-lane";
import { MarriedMixWaveform } from "@/components/tts/married-mix-waveform";

const LANE_ACCENTS = [
  undefined,
  "text-amber-700 dark:text-amber-300",
  "text-violet-700 dark:text-violet-300",
  "text-emerald-700 dark:text-emerald-300",
  "text-rose-700 dark:text-rose-300",
  "text-orange-700 dark:text-orange-300",
];

function layersDirty(local: AmbienceLayer[], server: AmbienceLayer[]): boolean {
  if (local.length !== server.length) return true;
  return local.some((layer, index) => {
    const other = server[index];
    return (
      layer.id !== other.id ||
      layer.assetId !== other.assetId ||
      Math.abs(layer.gainDb - other.gainDb) > 0.01 ||
      Math.abs(layer.offsetSeconds - other.offsetSeconds) > 0.05 ||
      Math.abs(layer.startSeconds - other.startSeconds) > 0.02 ||
      (layer.endSeconds == null) !== (other.endSeconds == null) ||
      (layer.endSeconds != null &&
        other.endSeconds != null &&
        Math.abs(layer.endSeconds - other.endSeconds) > 0.02)
    );
  });
}

function layerInWindow(layer: AmbienceLayer, playhead: number, takeDuration: number) {
  const end = layer.endSeconds ?? takeDuration;
  return playhead >= layer.startSeconds && playhead < end;
}

export type AmbienceMixContext = {
  collectionId: string;
  scenarioSlug: string;
  scenario: DialogueScenario;
  ambienceMixHash: string | null;
};

export function AmbienceMixTab({
  context,
  projectId,
  variantId,
  takeDuration,
  playheadSeconds,
  takePlaying,
  isSelectedTake,
  hasUnsavedChanges,
  active,
  onMarriedChange,
}: {
  context: AmbienceMixContext;
  projectId: string;
  variantId: string;
  takeDuration: number;
  playheadSeconds: number;
  takePlaying: boolean;
  isSelectedTake: boolean;
  hasUnsavedChanges?: boolean;
  active: boolean;
  onMarriedChange?: (married: boolean) => void;
}) {
  const { collectionId, scenarioSlug, scenario, ambienceMixHash } = context;
  const queryClient = useQueryClient();
  const { data } = useQuery({
    queryKey: ["ambience-assets"],
    queryFn: () => ttsApi.listAmbience(),
  });
  const assets = data?.assets ?? [];
  const assetById = new Map(assets.map((asset) => [asset.id, asset]));
  const serverLayers = layersFromScenario(scenario);

  const [uploadKind, setUploadKind] = useState("other");
  const [layers, setLayers] = useState<AmbienceLayer[]>(serverLayers);
  const [encodedUrl, setEncodedUrl] = useState<string | null>(null);
  const [encodedPlaying, setEncodedPlaying] = useState(false);
  const dirtyRef = useRef(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const bedsRef = useRef<Map<string, HTMLAudioElement>>(new Map());
  const encodedUrlRef = useRef<string | null>(null);

  useEffect(() => {
    if (dirtyRef.current) return;
    setLayers(serverLayers);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scenario.ambienceAssetId, scenario.ambienceLayers, scenario.updatedAt]);

  const dirty = layersDirty(layers, serverLayers);
  const mixStale =
    !!scenario.publishedAudioUrl &&
    (scenario.publishedAmbienceHash ?? null) !== (ambienceMixHash ?? null);
  const mixLive = !!scenario.publishedAudioUrl && !mixStale;
  const publishedAtLabel = formatPublishedAt(scenario.publishedAt);
  const married = encodedUrl != null;
  const canAdd = layers.length < MAX_AMBIENCE_LAYERS;

  useEffect(() => {
    onMarriedChange?.(married);
    return () => onMarriedChange?.(false);
  }, [married, onMarriedChange]);

  useEffect(() => {
    if (!active) setEncodedPlaying(false);
  }, [active]);

  function discardEncoded() {
    setEncodedPlaying(false);
    if (encodedUrlRef.current) {
      URL.revokeObjectURL(encodedUrlRef.current);
      encodedUrlRef.current = null;
    }
    setEncodedUrl(null);
  }

  function stopBeds() {
    for (const bed of bedsRef.current.values()) {
      bed.pause();
    }
  }

  useEffect(() => {
    function onStopPreview() {
      setEncodedPlaying(false);
    }
    function onToggleMarried() {
      setEncodedPlaying((prev) => !prev);
    }
    window.addEventListener(STUDIO_STOP_AMBIENCE_PREVIEW, onStopPreview);
    window.addEventListener(STUDIO_TOGGLE_MARRIED_MIX, onToggleMarried);
    return () => {
      window.removeEventListener(STUDIO_STOP_AMBIENCE_PREVIEW, onStopPreview);
      window.removeEventListener(STUDIO_TOGGLE_MARRIED_MIX, onToggleMarried);
      discardEncoded();
      stopBeds();
      bedsRef.current.clear();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (married) {
      stopBeds();
      return;
    }
    const keep = new Set(layers.map((layer) => layer.id));
    for (const [id, bed] of bedsRef.current) {
      if (!keep.has(id)) {
        bed.pause();
        bedsRef.current.delete(id);
      }
    }
    for (const layer of layers) {
      const asset = assetById.get(layer.assetId);
      if (!asset) continue;
      let bed = bedsRef.current.get(layer.id);
      if (!bed || bed.dataset.assetId !== layer.assetId) {
        bed?.pause();
        bed = new Audio(ttsApi.ambienceAudioUrl(layer.assetId));
        bed.loop = true;
        bed.preload = "auto";
        bed.dataset.assetId = layer.assetId;
        bedsRef.current.set(layer.id, bed);
      }
      bed.volume = gainDbToLinear(layer.gainDb);
      const inWindow =
        takePlaying && layerInWindow(layer, playheadSeconds, takeDuration);
      if (inWindow) {
        const intoWindow = Math.max(0, playheadSeconds - layer.startSeconds);
        const target = wrapAmbienceOffset(
          layer.offsetSeconds + intoWindow,
          asset.durationSeconds
        );
        if (Math.abs(bed.currentTime - target) > 0.12) {
          try {
            bed.currentTime = target;
          } catch {
            /* codec may reject until metadata */
          }
        }
        if (bed.paused) void bed.play().catch(() => {});
      } else {
        bed.pause();
      }
    }
  }, [
    layers,
    assets,
    takePlaying,
    playheadSeconds,
    takeDuration,
    married,
  ]);

  const saveMutation = useMutation({
    mutationFn: (next: AmbienceLayer[]) =>
      dialogueApi.updateScenarioAmbience(collectionId, scenarioSlug, {
        layers: next,
      }),
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

  function persistLayers(next: AmbienceLayer[], toastMessage?: string) {
    dirtyRef.current = false;
    setLayers(next);
    saveMutation.mutate(next, {
      onSuccess: () => {
        if (toastMessage) toast.success(toastMessage);
      },
    });
  }

  const uploadMutation = useMutation({
    mutationFn: async (file: File) => {
      const title = file.name.replace(/\.[^.]+$/, "") || "Ambience";
      const { asset } = await ttsApi.uploadAmbience({
        file,
        title,
        kind: uploadKind,
      });
      const layer = createAmbienceLayer({
        assetId: asset.id,
        bedDuration: asset.durationSeconds,
        takeDuration,
        playheadSeconds,
        full: layers.length === 0,
      });
      const next = [...layers, layer].slice(0, MAX_AMBIENCE_LAYERS);
      dirtyRef.current = false;
      await dialogueApi.updateScenarioAmbience(collectionId, scenarioSlug, {
        layers: next,
      });
      return { asset, next };
    },
    onSuccess: ({ asset, next }) => {
      discardEncoded();
      setLayers(next);
      queryClient.invalidateQueries({ queryKey: ["ambience-assets"] });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-scenario", collectionId, scenarioSlug],
      });
      toast.success(
        layers.length === 0
          ? `Attached “${asset.title}” under this scene.`
          : `Added “${asset.title}” as another bed.`
      );
    },
    onError: (error) => toast.error(error.message),
  });

  const encodeMutation = useMutation({
    mutationFn: async () => {
      if (layers.length === 0) throw new Error("Attach an ambience loop first.");
      if (dirty) {
        await dialogueApi.updateScenarioAmbience(collectionId, scenarioSlug, {
          layers,
        });
        dirtyRef.current = false;
      }
      const res = await fetch(
        `/api/content/dialogues/${collectionId}/scenarios/${scenarioSlug}/ambience/preview`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            variantId,
            layers: layers.map((layer) => ({
              assetId: layer.assetId,
              gainDb: layer.gainDb,
              offsetSeconds: layer.offsetSeconds,
              startSeconds: layer.startSeconds,
              endSeconds: layer.endSeconds,
            })),
          }),
        }
      );
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(
          typeof body?.error === "string" ? body.error : "Encode failed."
        );
      }
      return res.blob();
    },
    onSuccess: (blob) => {
      window.dispatchEvent(new Event(STUDIO_PAUSE_TAKE_AUDIO));
      if (encodedUrlRef.current) URL.revokeObjectURL(encodedUrlRef.current);
      const url = URL.createObjectURL(blob);
      encodedUrlRef.current = url;
      setEncodedUrl(url);
      setEncodedPlaying(true);
      queryClient.invalidateQueries({
        queryKey: ["dialogue-scenario", collectionId, scenarioSlug],
      });
      toast.success("Mix encoded — this is the clip publish will ship.");
    },
    onError: (error) => toast.error(error.message),
  });

  const publishMutation = useMutation({
    mutationFn: async () => {
      if (!isSelectedTake) {
        await ttsApi.selectVariant(projectId, variantId);
      }
      await flushPendingTokenSync();
      return dialogueApi.publishScenario(collectionId, scenarioSlug);
    },
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
      queryClient.invalidateQueries({ queryKey: ["scenario-audio"] });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-scenario", collectionId, scenarioSlug],
      });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-collection-audio-status", collectionId],
      });
      toast.success(
        result.hasTokenKaraoke
          ? "Published with token karaoke."
          : "Published to the learner CDN."
      );
    },
    onError: (error) => toast.error(error.message),
  });

  function patchLayer(id: string, patch: Partial<AmbienceLayer>) {
    dirtyRef.current = true;
    discardEncoded();
    setLayers((prev) =>
      prev.map((layer) => (layer.id === id ? { ...layer, ...patch } : layer))
    );
  }

  function addAsset(assetId: string) {
    const asset = assets.find((item) => item.id === assetId);
    if (!asset || !canAdd) return;
    discardEncoded();
    persistLayers(
      [
        ...layers,
        createAmbienceLayer({
          assetId,
          bedDuration: asset.durationSeconds,
          takeDuration,
          playheadSeconds,
          full: layers.length === 0,
        }),
      ],
      layers.length === 0
        ? `Attached “${asset.title}” under this scene.`
        : `Added “${asset.title}”.`
    );
  }

  function removeLayer(id: string) {
    discardEncoded();
    persistLayers(
      layers.filter((layer) => layer.id !== id),
      "Removed bed."
    );
  }

  function lockMix() {
    if (layers.length === 0) return;
    persistLayers(layers, "Mix locked for this scene.");
  }

  const grouped = groupAmbienceAssets(assets);

  function assetLabel(asset: AmbienceAsset | undefined, fallback: string) {
    return asset?.title ?? fallback;
  }

  if (married && encodedUrl) {
    return (
      <div className="flex flex-col gap-3">
        <MarriedMixWaveform
          url={encodedUrl}
          playing={encodedPlaying}
          onPlayingChange={setEncodedPlaying}
        />
        <div className="flex flex-wrap items-center gap-2">
          <Button
            type="button"
            size="sm"
            onClick={() => setEncodedPlaying((prev) => !prev)}
          >
            {encodedPlaying ? (
              <>
                <Pause className="mr-1" />
                Pause mix
              </>
            ) : (
              <>
                <Play className="mr-1" />
                Play mix
              </>
            )}
          </Button>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => {
              setEncodedPlaying(false);
              discardEncoded();
            }}
          >
            <SlidersHorizontal className="mr-1" />
            Adjust mix
          </Button>
          <Button
            type="button"
            size="sm"
            disabled={
              hasUnsavedChanges || publishMutation.isPending || mixLive
            }
            onClick={() => publishMutation.mutate()}
          >
            {publishMutation.isPending ? (
              "Publishing…"
            ) : mixLive ? (
              <>
                <Check className="mr-1" />
                Published
              </>
            ) : scenario.publishedAudioUrl ? (
              "Republish"
            ) : (
              "Publish"
            )}
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">
          {mixLive
            ? `This mix is live${
                publishedAtLabel ? ` · last published ${publishedAtLabel}` : ""
              }. Adjust mix if you need to change beds or levels.`
            : "This bake is Studio-only. Publish ships dry dialogue plus the first looping bed — same as Publish scenario audio above."}
        </p>
        {hasUnsavedChanges ? (
          <p className="text-xs text-amber-600 dark:text-amber-400">
            Save line edits before publishing.
          </p>
        ) : null}
        {mixStale ? (
          <p className="text-xs text-amber-600 dark:text-amber-400">
            Last published {publishedAtLabel ?? "earlier"} — this bed setup is
            newer. Republish to update the learner bed metadata.
          </p>
        ) : null}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="text-xs text-muted-foreground">
        Continuous atmosphere only — crowd, cafe, street wash. No
        announcements, stings, or story SFX; those belong on the dry take.
        Play the take here to check level; the app loops the first bed under
        scene listen.
      </p>
      {layers.length > 0 && takeDuration > 0
        ? layers.map((layer, index) => {
            const asset = assetById.get(layer.assetId);
            if (!asset) {
              return (
                <div
                  key={layer.id}
                  className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-border/70 p-2"
                >
                  <p className="text-sm text-muted-foreground">
                    This bed is missing from the library.
                  </p>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => removeLayer(layer.id)}
                  >
                    <Trash2 className="mr-1" />
                    Remove
                  </Button>
                </div>
              );
            }
            const end = layer.endSeconds ?? takeDuration;
            return (
              <div
                key={layer.id}
                className="flex flex-col gap-2 rounded-md border border-border/70 p-2"
              >
                <AmbienceLane
                  audioUrl={ttsApi.ambienceAudioUrl(asset.id)}
                  bedDuration={asset.durationSeconds}
                  takeDuration={takeDuration}
                  offsetSeconds={layer.offsetSeconds}
                  startSeconds={layer.startSeconds}
                  endSeconds={layer.endSeconds}
                  playheadSeconds={playheadSeconds}
                  label={assetLabel(asset, `Bed ${index + 1}`)}
                  accentClassName={LANE_ACCENTS[index % LANE_ACCENTS.length]}
                  onWindowChange={(next) => patchLayer(layer.id, next)}
                  onOffsetChange={(next) =>
                    patchLayer(
                      layer.id,
                      { offsetSeconds: wrapAmbienceOffset(next, asset.durationSeconds) }
                    )
                  }
                />
                <div className="flex max-w-xl flex-col gap-1">
                  <Label htmlFor={`ambience-gain-${layer.id}`}>
                    Volume {layer.gainDb.toFixed(0)} dB
                  </Label>
                  <input
                    id={`ambience-gain-${layer.id}`}
                    type="range"
                    min={MIN_AMBIENCE_GAIN_DB}
                    max={MAX_AMBIENCE_GAIN_DB}
                    step={1}
                    value={layer.gainDb}
                    onChange={(event) =>
                      patchLayer(layer.id, { gainDb: Number(event.target.value) })
                    }
                    className="h-2 w-full cursor-pointer appearance-none rounded-full bg-muted accent-primary"
                  />
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-xs text-muted-foreground">
                    {formatAmbienceSeconds(layer.startSeconds)}–
                    {formatAmbienceSeconds(end)} on take · loop{" "}
                    {formatAmbienceSeconds(layer.offsetSeconds)} /{" "}
                    {formatAmbienceSeconds(asset.durationSeconds)}
                  </span>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() =>
                      patchLayer(layer.id, {
                        offsetSeconds: randomAmbienceOffset(asset.durationSeconds),
                      })
                    }
                  >
                    <Shuffle className="mr-1" />
                    Randomize
                  </Button>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() =>
                      patchLayer(layer.id, { startSeconds: 0, endSeconds: null })
                    }
                  >
                    Whole take
                  </Button>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => removeLayer(layer.id)}
                  >
                    <Trash2 className="mr-1" />
                    Remove
                  </Button>
                </div>
              </div>
            );
          })
        : null}

      <div className="flex flex-wrap items-end gap-3">
        <div className="flex min-w-56 flex-1 flex-col gap-2">
          <Label>{layers.length === 0 ? "Ambience" : "Add another bed"}</Label>
          <Select
            key={layers.map((layer) => layer.id).join("-") || "empty"}
            disabled={!canAdd}
            onValueChange={(value) => {
              if (value) addAsset(value);
            }}
          >
            <SelectTrigger className="w-full">
              <SelectValue
                placeholder={
                  layers.length === 0 ? "Off (dry dialogue)" : "Add another bed"
                }
              />
            </SelectTrigger>
            <SelectContent>
              {grouped.map((group) => (
                <SelectGroup key={group.kind}>
                  <SelectLabel>{group.label}</SelectLabel>
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
        <div className="flex w-44 flex-col gap-2">
          <Label htmlFor="ambience-upload-kind">Type</Label>
          <AmbienceKindField
            id="ambience-upload-kind"
            value={uploadKind}
            compact
            onChange={setUploadKind}
          />
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
          size="sm"
          disabled={uploadMutation.isPending || !canAdd}
          onClick={() => fileInputRef.current?.click()}
        >
          <Upload className="mr-1 size-3.5" />
          {uploadMutation.isPending
            ? "Uploading…"
            : layers.length === 0
              ? "Upload & attach"
              : "Upload layer"}
        </Button>
        <Link
          href="/tts/ambience"
          className="pb-1 text-xs text-muted-foreground hover:text-foreground"
        >
          Manage library
        </Link>
      </div>

      {layers.length > 0 ? (
        <>
          <div className="flex flex-wrap items-center gap-2">
            <Button
              type="button"
              size="sm"
              disabled={!dirty || saveMutation.isPending}
              onClick={lockMix}
            >
              <Lock className="mr-1" />
              {saveMutation.isPending ? "Locking…" : dirty ? "Lock mix" : "Locked"}
            </Button>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={encodeMutation.isPending}
              onClick={() => encodeMutation.mutate()}
            >
              {encodeMutation.isPending ? (
                <>
                  <WandSparkles className="mr-1" />
                  Encoding…
                </>
              ) : (
                <>
                  <WandSparkles className="mr-1" />
                  Preview bake
                </>
              )}
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            The learner app plays the first bed as a loop under dry dialogue.
            Extra layers and windows are Studio preview only.
            {layers.length > 1
              ? " This scene has extra layers — only the first bed ships."
              : ""}
            {layers.length >= MAX_AMBIENCE_LAYERS
              ? ` ${MAX_AMBIENCE_LAYERS} beds max.`
              : ""}
          </p>
        </>
      ) : (
        <p className="text-sm text-muted-foreground">
          Attach a continuous loop to hear it under this take. The app plays
          that bed independently so it keeps going through stage-line pauses.
        </p>
      )}

      {mixStale ? (
        <p className="text-xs text-amber-600 dark:text-amber-400">
          Last published {publishedAtLabel ?? "earlier"} — locked bed changed
          since then. Republish to update the learner bed metadata.
        </p>
      ) : mixLive && publishedAtLabel ? (
        <p className="text-xs text-muted-foreground">
          This mix is live · last published {publishedAtLabel}.
        </p>
      ) : null}
    </div>
  );
}
