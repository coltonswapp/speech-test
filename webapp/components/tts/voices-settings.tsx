"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2, Pause, Play } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import {
  ttsApi,
  type PairRatingValue,
  type TtsVoicePairRating,
  type TtsVoiceProfile,
  type VoiceGender,
  type VoicePreview,
} from "@/lib/tts/client";
import { cn } from "@/lib/utils";

const GENDER_OPTIONS: { value: VoiceGender; label: string }[] = [
  { value: "female", label: "Female" },
  { value: "male", label: "Male" },
  { value: "neutral", label: "Neutral" },
  { value: "unknown", label: "Unknown" },
];

const RATING_CYCLE: Array<PairRatingValue | null> = [
  null,
  "green",
  "yellow",
  "red",
];

const RATING_CLASS: Record<PairRatingValue, string> = {
  green: "bg-emerald-500/85 hover:bg-emerald-500 text-white",
  yellow: "bg-amber-400/90 hover:bg-amber-400 text-amber-950",
  red: "bg-rose-500/85 hover:bg-rose-500 text-white",
};

function sortedPairKey(a: string, b: string): string {
  return a < b ? `${a}::${b}` : `${b}::${a}`;
}

function nextRating(current: PairRatingValue | null): PairRatingValue | null {
  const idx = RATING_CYCLE.indexOf(current);
  return RATING_CYCLE[(idx + 1) % RATING_CYCLE.length] ?? null;
}

function previewFor(
  previews: VoicePreview[] | undefined,
  voice: string
): VoicePreview | undefined {
  return previews?.find((p) => p.provider === "gemini" && p.voice === voice);
}

function usePreviewPlayer() {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const queueRef = useRef<Array<{ url: string; label: string }>>([]);
  const [playingVoice, setPlayingVoice] = useState<string | null>(null);
  const [loadingVoice, setLoadingVoice] = useState<string | null>(null);

  const stop = () => {
    if (audioRef.current) {
      audioRef.current.onended = null;
      audioRef.current.pause();
    }
    queueRef.current = [];
    setPlayingVoice(null);
    setLoadingVoice(null);
  };

  const playNext = () => {
    const next = queueRef.current.shift();
    if (!next || !audioRef.current) {
      setPlayingVoice(null);
      setLoadingVoice(null);
      return;
    }
    setLoadingVoice(next.label);
    setPlayingVoice(next.label);
    audioRef.current.src = next.url;
    audioRef.current.play().catch(() => stop());
  };

  const ensureAudio = () => {
    if (!audioRef.current) {
      audioRef.current = new Audio();
      audioRef.current.onplay = () => setLoadingVoice(null);
    }
    audioRef.current.onended = () => playNext();
    return audioRef.current;
  };

  const playUrl = (url: string, voiceLabel: string) => {
    if (playingVoice === voiceLabel && queueRef.current.length === 0) {
      stop();
      return;
    }
    const audio = ensureAudio();
    queueRef.current = [];
    setLoadingVoice(voiceLabel);
    setPlayingVoice(voiceLabel);
    audio.src = url;
    audio.play().catch(() => stop());
  };

  const playSequence = (items: Array<{ url: string; label: string }>) => {
    if (items.length === 0) return;
    if (
      playingVoice &&
      items.some((item) => item.label === playingVoice)
    ) {
      stop();
      return;
    }
    const audio = ensureAudio();
    const [first, ...rest] = items;
    queueRef.current = rest;
    setLoadingVoice(first.label);
    setPlayingVoice(first.label);
    audio.src = first.url;
    audio.play().catch(() => stop());
  };

  useEffect(() => () => stop(), []);

  return { playUrl, playSequence, stop, playingVoice, loadingVoice };
}

function VoiceNotesCell({
  profile,
  onSave,
}: {
  profile: TtsVoiceProfile;
  onSave: (notes: string) => void;
}) {
  return (
    <Textarea
      key={profile.id}
      defaultValue={profile.notes}
      onBlur={(event) => {
        const next = event.target.value;
        if (next !== profile.notes) onSave(next);
      }}
      placeholder="Cast notes — tone, age, accent…"
      className="min-h-14 text-sm"
      rows={2}
    />
  );
}

function VoiceTable({
  profiles,
  previews,
  onGenderChange,
  onNotesChange,
  player,
}: {
  profiles: TtsVoiceProfile[];
  previews: VoicePreview[] | undefined;
  onGenderChange: (id: string, gender: VoiceGender) => void;
  onNotesChange: (id: string, notes: string) => void;
  player: ReturnType<typeof usePreviewPlayer>;
}) {
  return (
    <div className="overflow-x-auto rounded-md border border-border/60">
      <table className="w-full min-w-[40rem] text-left text-sm">
        <thead className="border-b border-border/60 bg-muted/40 text-muted-foreground">
          <tr>
            <th className="px-3 py-2 font-medium">Voice</th>
            <th className="w-36 px-3 py-2 font-medium">Gender</th>
            <th className="px-3 py-2 font-medium">Notes</th>
            <th className="w-14 px-3 py-2 font-medium">Play</th>
          </tr>
        </thead>
        <tbody>
          {profiles.map((profile) => {
            const preview = previewFor(previews, profile.voice);
            const isPlaying = player.playingVoice === profile.voice;
            const isLoading = player.loadingVoice === profile.voice;
            return (
              <tr
                key={profile.id}
                className="border-b border-border/40 last:border-0"
              >
                <td className="px-3 py-2 align-top font-medium">
                  {profile.voice}
                </td>
                <td className="px-3 py-2 align-top">
                  <Select
                    value={profile.gender}
                    onValueChange={(value) => {
                      if (value) onGenderChange(profile.id, value as VoiceGender);
                    }}
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectGroup>
                        {GENDER_OPTIONS.map((opt) => (
                          <SelectItem key={opt.value} value={opt.value}>
                            {opt.label}
                          </SelectItem>
                        ))}
                      </SelectGroup>
                    </SelectContent>
                  </Select>
                </td>
                <td className="px-3 py-2 align-top">
                  <VoiceNotesCell
                    profile={profile}
                    onSave={(notes) => onNotesChange(profile.id, notes)}
                  />
                </td>
                <td className="px-3 py-2 align-top">
                  <Button
                    type="button"
                    variant="outline"
                    size="icon"
                    disabled={!preview}
                    title={
                      preview
                        ? `Preview ${profile.voice}`
                        : "No preview available"
                    }
                    onClick={() => {
                      if (!preview) return;
                      player.playUrl(
                        `/api/tts/voice-previews/${preview.id}/audio`,
                        profile.voice
                      );
                    }}
                  >
                    {isLoading ? (
                      <Loader2 className="size-4 animate-spin" />
                    ) : isPlaying ? (
                      <Pause className="size-4" />
                    ) : (
                      <Play className="size-4" />
                    )}
                  </Button>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function PairingMatrix({
  voices,
  ratings,
  onCycle,
  pendingKey,
}: {
  voices: string[];
  ratings: Map<string, PairRatingValue>;
  onCycle: (voiceA: string, voiceB: string, next: PairRatingValue | null) => void;
  pendingKey: string | null;
}) {
  if (voices.length < 2) {
    return (
      <p className="text-sm text-muted-foreground">
        Tag at least two voices with this gender to build a pairing matrix.
      </p>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="border-collapse text-xs">
        <thead>
          <tr>
            <th className="sticky left-0 z-10 bg-background p-1" />
            {voices.map((voice) => (
              <th
                key={voice}
                className="max-w-16 truncate p-1 font-medium text-muted-foreground"
                title={voice}
              >
                <span className="inline-block max-w-16 rotate-[-35deg] origin-bottom-left translate-y-2">
                  {voice}
                </span>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {voices.map((rowVoice, rowIdx) => (
            <tr key={rowVoice}>
              <th className="sticky left-0 z-10 bg-background px-2 py-1 text-left font-medium whitespace-nowrap">
                {rowVoice}
              </th>
              {voices.map((colVoice, colIdx) => {
                if (colIdx <= rowIdx) {
                  return (
                    <td key={colVoice} className="p-0.5">
                      <div className="size-8 rounded-sm bg-muted/40" />
                    </td>
                  );
                }
                const key = sortedPairKey(rowVoice, colVoice);
                const rating = ratings.get(key) ?? null;
                const busy = pendingKey === key;
                return (
                  <td key={colVoice} className="p-0.5">
                    <button
                      type="button"
                      disabled={busy}
                      title={`${rowVoice} × ${colVoice}: ${rating ?? "unset"} (click to cycle)`}
                      aria-label={`${rowVoice} and ${colVoice} pair rating ${rating ?? "unset"}`}
                      className={cn(
                        "flex size-8 items-center justify-center rounded-sm border border-border/50 transition-colors",
                        rating
                          ? RATING_CLASS[rating]
                          : "bg-background hover:bg-muted text-muted-foreground"
                      )}
                      onClick={() =>
                        onCycle(rowVoice, colVoice, nextRating(rating))
                      }
                    >
                      {busy ? (
                        <Loader2 className="size-3 animate-spin" />
                      ) : rating ? (
                        <span className="sr-only">{rating}</span>
                      ) : (
                        <span className="text-[10px] opacity-40">·</span>
                      )}
                    </button>
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
      <div className="mt-3 flex flex-wrap items-center gap-3 text-xs text-muted-foreground">
        <span>Click a cell to cycle:</span>
        <span className="inline-flex items-center gap-1.5">
          <span className="size-3 rounded-sm border border-border/50 bg-background" />
          unset
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className={cn("size-3 rounded-sm", RATING_CLASS.green)} />
          green — clear
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className={cn("size-3 rounded-sm", RATING_CLASS.yellow)} />
          yellow — close
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className={cn("size-3 rounded-sm", RATING_CLASS.red)} />
          red — confuse
        </span>
      </div>
    </div>
  );
}

function AbListen({
  profiles,
  previews,
  player,
}: {
  profiles: TtsVoiceProfile[];
  previews: VoicePreview[] | undefined;
  player: ReturnType<typeof usePreviewPlayer>;
}) {
  const voices = profiles.map((p) => p.voice);
  const [voiceA, setVoiceA] = useState<string | null>(null);
  const [voiceB, setVoiceB] = useState<string | null>(null);

  const selectedA =
    voiceA && voices.includes(voiceA) ? voiceA : (voices[0] ?? "");
  const selectedB =
    voiceB && voices.includes(voiceB)
      ? voiceB
      : (voices[1] ?? voices[0] ?? "");

  const previewA = previewFor(previews, selectedA);
  const previewB = previewFor(previews, selectedB);
  const canPlay = Boolean(
    previewA && previewB && selectedA && selectedB && selectedA !== selectedB
  );
  const isPlayingAb =
    player.playingVoice === selectedA || player.playingVoice === selectedB;

  return (
    <div className="flex flex-col gap-4 sm:flex-row sm:items-end">
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <Label>Voice A</Label>
        <Select
          value={selectedA}
          onValueChange={(value) => {
            if (value) setVoiceA(value);
          }}
        >
          <SelectTrigger className="w-full">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectGroup>
              {voices.map((voice) => (
                <SelectItem key={voice} value={voice}>
                  {voice}
                </SelectItem>
              ))}
            </SelectGroup>
          </SelectContent>
        </Select>
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <Label>Voice B</Label>
        <Select
          value={selectedB}
          onValueChange={(value) => {
            if (value) setVoiceB(value);
          }}
        >
          <SelectTrigger className="w-full">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectGroup>
              {voices.map((voice) => (
                <SelectItem key={voice} value={voice}>
                  {voice}
                </SelectItem>
              ))}
            </SelectGroup>
          </SelectContent>
        </Select>
      </div>
      <Button
        type="button"
        disabled={!canPlay && !isPlayingAb}
        title={
          !previewA || !previewB
            ? "Both voices need a preview clip"
            : selectedA === selectedB
              ? "Pick two different voices"
              : `Play ${selectedA} then ${selectedB}`
        }
        onClick={() => {
          if (isPlayingAb) {
            player.stop();
            return;
          }
          if (!previewA || !previewB) return;
          player.playSequence([
            {
              url: `/api/tts/voice-previews/${previewA.id}/audio`,
              label: selectedA,
            },
            {
              url: `/api/tts/voice-previews/${previewB.id}/audio`,
              label: selectedB,
            },
          ]);
        }}
      >
        {isPlayingAb ? (
          <>
            <Pause className="size-4" />
            Stop
          </>
        ) : (
          <>
            <Play className="size-4" />
            Play A → B
          </>
        )}
      </Button>
    </div>
  );
}

export function VoicesSettings() {
  const queryClient = useQueryClient();
  const player = usePreviewPlayer();
  const [matrixGender, setMatrixGender] = useState<"female" | "male">("female");
  const [pendingPairKey, setPendingPairKey] = useState<string | null>(null);

  const profilesQuery = useQuery({
    queryKey: ["tts-voice-profiles", "gemini"],
    queryFn: () => ttsApi.listVoiceProfiles("gemini"),
  });

  const previewsQuery = useQuery({
    queryKey: ["voice-previews"],
    queryFn: () => ttsApi.listVoicePreviews(),
    staleTime: Infinity,
  });

  const pairsQuery = useQuery({
    queryKey: ["tts-voice-pairs", "gemini"],
    queryFn: () => ttsApi.listVoicePairRatings({ provider: "gemini" }),
  });

  const updateMutation = useMutation({
    mutationFn: (params: {
      id: string;
      gender?: VoiceGender;
      notes?: string;
    }) => ttsApi.updateVoiceProfile(params.id, params),
    onMutate: async (params) => {
      await queryClient.cancelQueries({
        queryKey: ["tts-voice-profiles", "gemini"],
      });
      const previous = queryClient.getQueryData<{ profiles: TtsVoiceProfile[] }>([
        "tts-voice-profiles",
        "gemini",
      ]);
      if (previous) {
        queryClient.setQueryData(["tts-voice-profiles", "gemini"], {
          profiles: previous.profiles.map((profile) =>
            profile.id === params.id
              ? {
                  ...profile,
                  gender: params.gender ?? profile.gender,
                  notes: params.notes ?? profile.notes,
                }
              : profile
          ),
        });
      }
      return { previous };
    },
    onError: (err, _params, context) => {
      if (context?.previous) {
        queryClient.setQueryData(
          ["tts-voice-profiles", "gemini"],
          context.previous
        );
      }
      toast.error(err.message);
    },
    onSettled: () => {
      queryClient.invalidateQueries({
        queryKey: ["tts-voice-profiles", "gemini"],
      });
    },
  });

  const pairMutation = useMutation({
    mutationFn: (params: {
      voiceA: string;
      voiceB: string;
      rating: PairRatingValue | null;
    }) => ttsApi.upsertVoicePairRating(params),
    onMutate: async (params) => {
      const key = sortedPairKey(params.voiceA, params.voiceB);
      setPendingPairKey(key);
      await queryClient.cancelQueries({ queryKey: ["tts-voice-pairs", "gemini"] });
      const previous = queryClient.getQueryData<{
        ratings: TtsVoicePairRating[];
      }>(["tts-voice-pairs", "gemini"]);
      if (previous) {
        const [voiceA, voiceB] =
          params.voiceA < params.voiceB
            ? [params.voiceA, params.voiceB]
            : [params.voiceB, params.voiceA];
        const without = previous.ratings.filter(
          (row) =>
            !(
              row.provider === "gemini" &&
              row.voiceA === voiceA &&
              row.voiceB === voiceB
            )
        );
        const nextRatings =
          params.rating === null
            ? without
            : [
                ...without,
                {
                  id: `optimistic-${key}`,
                  createdAt: new Date().toISOString(),
                  updatedAt: new Date().toISOString(),
                  provider: "gemini",
                  voiceA,
                  voiceB,
                  rating: params.rating,
                  notes: null,
                } satisfies TtsVoicePairRating,
              ];
        queryClient.setQueryData(["tts-voice-pairs", "gemini"], {
          ratings: nextRatings,
        });
      }
      return { previous };
    },
    onError: (err, _params, context) => {
      if (context?.previous) {
        queryClient.setQueryData(
          ["tts-voice-pairs", "gemini"],
          context.previous
        );
      }
      toast.error(err.message);
    },
    onSettled: () => {
      setPendingPairKey(null);
      queryClient.invalidateQueries({ queryKey: ["tts-voice-pairs", "gemini"] });
    },
  });

  const profiles = useMemo(
    () => profilesQuery.data?.profiles ?? [],
    [profilesQuery.data?.profiles]
  );
  const matrixVoices = useMemo(
    () =>
      profiles
        .filter((profile) => profile.gender === matrixGender)
        .map((profile) => profile.voice),
    [profiles, matrixGender]
  );

  const ratingMap = useMemo(() => {
    const map = new Map<string, PairRatingValue>();
    for (const row of pairsQuery.data?.ratings ?? []) {
      map.set(sortedPairKey(row.voiceA, row.voiceB), row.rating);
    }
    return map;
  }, [pairsQuery.data?.ratings]);

  if (profilesQuery.isLoading) {
    return (
      <div className="flex flex-col gap-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  if (profilesQuery.isError) {
    return (
      <p className="text-sm text-destructive">
        {profilesQuery.error.message || "Could not load voice profiles."}
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardTitle className="text-base font-medium">
            Gemini voice catalog
          </CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          <p className="text-sm text-muted-foreground">
            Set gender and casting notes so same-gender F–F / M–M pairs are
            easier to plan. Play uses existing voice previews when present.
          </p>
          <VoiceTable
            profiles={profiles}
            previews={previewsQuery.data?.previews}
            player={player}
            onGenderChange={(id, gender) =>
              updateMutation.mutate({ id, gender })
            }
            onNotesChange={(id, notes) => updateMutation.mutate({ id, notes })}
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-3 space-y-0">
          <CardTitle className="text-base font-medium">
            Pairing matrix
          </CardTitle>
          <div className="flex items-center gap-1 rounded-lg bg-muted p-[3px]">
            {(["female", "male"] as const).map((gender) => (
              <button
                key={gender}
                type="button"
                className={cn(
                  "inline-flex h-7 items-center rounded-md px-3 text-sm font-medium transition-colors",
                  matrixGender === gender
                    ? "bg-background text-foreground shadow-sm"
                    : "text-muted-foreground hover:text-foreground"
                )}
                onClick={() => setMatrixGender(gender)}
              >
                {gender === "female" ? "Female × female" : "Male × male"}
              </button>
            ))}
          </div>
        </CardHeader>
        <CardContent>
          <PairingMatrix
            voices={matrixVoices}
            ratings={ratingMap}
            pendingKey={pendingPairKey}
            onCycle={(voiceA, voiceB, rating) =>
              pairMutation.mutate({ voiceA, voiceB, rating })
            }
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base font-medium">A/B listen</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          <p className="text-sm text-muted-foreground">
            Play the same preview line for two voices back-to-back when both
            clips exist.
          </p>
          <AbListen
            profiles={profiles}
            previews={previewsQuery.data?.previews}
            player={player}
          />
        </CardContent>
      </Card>
    </div>
  );
}
