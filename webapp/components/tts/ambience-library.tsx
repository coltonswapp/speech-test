"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Trash2, Upload } from "lucide-react";
import { Button, buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { ttsApi, type AmbienceAsset } from "@/lib/tts/client";
import { formatAmbienceSeconds } from "@/lib/tts/ambience";
import { AmbienceKindField } from "@/components/tts/ambience-kind-field";

export function AmbienceLibrary() {
  const queryClient = useQueryClient();
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["ambience-assets"],
    queryFn: () => ttsApi.listAmbience(),
  });

  const [title, setTitle] = useState("");
  const [kind, setKind] = useState("cafe");
  const [file, setFile] = useState<File | null>(null);

  const uploadMutation = useMutation({
    mutationFn: () => {
      if (!file) throw new Error("Choose a WAV, MP3, or M4A loop.");
      return ttsApi.uploadAmbience({
        file,
        title: title.trim() || file.name.replace(/\.[^.]+$/, ""),
        kind,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ambience-assets"] });
      setTitle("");
      setFile(null);
      toast.success("Ambience bed added.");
    },
    onError: (err) => toast.error(err.message),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => ttsApi.deleteAmbience(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ambience-assets"] });
      toast.success("Bed removed.");
    },
    onError: (err) => toast.error(err.message),
  });

  const updateMutation = useMutation({
    mutationFn: (params: { id: string; title?: string; kind?: string }) =>
      ttsApi.updateAmbience(params.id, {
        title: params.title,
        kind: params.kind,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ambience-assets"] });
    },
    onError: (err) => toast.error(err.message),
  });

  const assets = data?.assets ?? [];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Ambience</h1>
        <p className="text-sm text-muted-foreground">
          Reusable continuous loops (street, cafe, crowd, …) — anonymous
          place-tone, not story beats. Attach a bed and gain on a take&apos;s
          Ambience tab; publish ships dry dialogue plus the bed for the app to
          loop. Karaoke still stamps the dry take.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base font-medium">Upload a bed</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <div className="grid max-w-2xl gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-2">
              <Label htmlFor="ambience-title">Title</Label>
              <Input
                id="ambience-title"
                value={title}
                onChange={(event) => setTitle(event.target.value)}
                placeholder="Cafe murmur"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="ambience-kind">Type</Label>
              <AmbienceKindField
                id="ambience-kind"
                value={kind}
                onChange={setKind}
              />
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <label className={buttonVariants({ variant: "outline" })}>
              <Upload className="mr-1 size-3.5" />
              {file ? file.name : "Choose WAV / MP3 / M4A"}
              <input
                type="file"
                accept="audio/wav,audio/wave,audio/x-wav,audio/mpeg,audio/mp3,audio/mp4,audio/m4a,audio/x-m4a,.wav,.mp3,.m4a"
                className="sr-only"
                onChange={(event) => setFile(event.target.files?.[0] ?? null)}
              />
            </label>
            <Button
              onClick={() => uploadMutation.mutate()}
              disabled={uploadMutation.isPending || !file}
            >
              {uploadMutation.isPending ? "Uploading…" : "Upload"}
            </Button>
          </div>
        </CardContent>
      </Card>

      {isLoading ? (
        <Skeleton className="h-40 w-full" />
      ) : isError ? (
        <p className="text-sm text-muted-foreground">
          {error instanceof Error ? error.message : "Failed to load beds."}
        </p>
      ) : assets.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          No beds yet. Upload a seamless loop to get started.
        </p>
      ) : (
        <ul className="flex flex-col gap-2">
          {assets.map((asset) => (
            <AmbienceAssetRow
              key={asset.id}
              asset={asset}
              busy={deleteMutation.isPending || updateMutation.isPending}
              onDelete={() => deleteMutation.mutate(asset.id)}
              onSave={(patch) =>
                updateMutation.mutate({ id: asset.id, ...patch })
              }
            />
          ))}
        </ul>
      )}
    </div>
  );
}

function AmbienceAssetRow({
  asset,
  busy,
  onDelete,
  onSave,
}: {
  asset: AmbienceAsset;
  busy: boolean;
  onDelete: () => void;
  onSave: (patch: { title?: string; kind?: string }) => void;
}) {
  return (
    <li className="flex flex-wrap items-center gap-2 rounded-md border border-border/60 px-3 py-2">
      <Input
        defaultValue={asset.title}
        className="max-w-xs"
        onBlur={(event) => {
          const next = event.target.value.trim();
          if (next && next !== asset.title) onSave({ title: next });
        }}
      />
      <div className="w-40">
        <AmbienceKindField
          value={asset.kind}
          compact
          onChange={(kind) => {
            if (kind !== asset.kind) onSave({ kind });
          }}
        />
      </div>
      <span className="text-xs text-muted-foreground">
        {formatAmbienceSeconds(asset.durationSeconds)}
      </span>
      <audio
        className="h-8 min-w-40 flex-1"
        controls
        preload="none"
        src={ttsApi.ambienceAudioUrl(asset.id)}
      />
      <Button
        type="button"
        variant="ghost"
        size="icon-sm"
        disabled={busy}
        onClick={onDelete}
        aria-label={`Delete ${asset.title}`}
      >
        <Trash2 className="size-3.5" />
      </Button>
    </li>
  );
}
