"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2, Pause, Play } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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

/**
 * Operator score 1–4 for a voice pairing.
 * Higher = more distinguishable. Maps onto existing green/yellow/red storage
 * (plus unset). Color treatment stays identical to the prior click-cycle UI.
 */
const PAIR_SCORES = [
  {
    score: 1 as const,
    rating: null,
    label: "Unset",
    hint: "No rating yet",
  },
  {
    score: 2 as const,
    rating: "red" as const,
    label: "Confuse",
    hint: "Hard to tell apart",
  },
  {
    score: 3 as const,
    rating: "yellow" as const,
    label: "Close",
    hint: "Borderline — similar",
  },
  {
    score: 4 as const,
    rating: "green" as const,
    label: "Clear",
    hint: "Easy to distinguish",
  },
];

type PairScore = (typeof PAIR_SCORES)[number]["score"];

const RATING_CLASS: Record<PairRatingValue, string> = {
  green: "bg-emerald-500/85 hover:bg-emerald-500 text-white",
  yellow: "bg-amber-400/90 hover:bg-amber-400 text-amber-950",
  red: "bg-rose-500/85 hover:bg-rose-500 text-white",
};

const SCORE_BUTTON_CLASS: Record<PairScore, string> = {
  1: "bg-background hover:bg-muted text-muted-foreground border-border",
  2: "bg-rose-500/85 hover:bg-rose-500 text-white border-rose-600/40",
  3: "bg-amber-400/90 hover:bg-amber-400 text-amber-950 border-amber-500/40",
  4: "bg-emerald-500/85 hover:bg-emerald-500 text-white border-emerald-600/40",
};

function sortedPairKey(a: string, b: string): string {
  return a < b ? `${a}::${b}` : `${b}::${a}`;
}

function scoreForRating(rating: PairRatingValue | null): PairScore {
  if (rating === "green") return 4;
  if (rating === "yellow") return 3;
  if (rating === "red") return 2;
  return 1;
}

function ratingForScore(score: PairScore): PairRatingValue | null {
  return PAIR_SCORES.find((option) => option.score === score)?.rating ?? null;
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
  const [playingPairKey, setPlayingPairKey] = useState<string | null>(null);
  const [loadingVoice, setLoadingVoice] = useState<string | null>(null);

  const stop = () => {
    if (audioRef.current) {
      audioRef.current.onended = null;
      audioRef.current.pause();
    }
    queueRef.current = [];
    setPlayingVoice(null);
    setPlayingPairKey(null);
    setLoadingVoice(null);
  };

  const playNext = () => {
    const next = queueRef.current.shift();
    if (!next || !audioRef.current) {
      setPlayingVoice(null);
      setPlayingPairKey(null);
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
    setPlayingPairKey(null);
    setLoadingVoice(voiceLabel);
    setPlayingVoice(voiceLabel);
    audio.src = url;
    audio.play().catch(() => stop());
  };

  const playSequence = (
    items: Array<{ url: string; label: string }>,
    pairKey?: string
  ) => {
    if (items.length === 0) return;
    if (pairKey && playingPairKey === pairKey) {
      stop();
      return;
    }
    if (
      !pairKey &&
      playingVoice &&
      items.some((item) => item.label === playingVoice)
    ) {
      stop();
      return;
    }
    const audio = ensureAudio();
    const [first, ...rest] = items;
    queueRef.current = rest;
    setPlayingPairKey(pairKey ?? null);
    setLoadingVoice(first.label);
    setPlayingVoice(first.label);
    audio.src = first.url;
    audio.play().catch(() => stop());
  };

  useEffect(() => () => stop(), []);

  return {
    playUrl,
    playSequence,
    stop,
    playingVoice,
    playingPairKey,
    loadingVoice,
  };
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

/** Every unordered same-gender pair — scored and unscored alike. */
function buildAllPairings(voices: string[]): Array<{
  voiceA: string;
  voiceB: string;
  key: string;
}> {
  const pairs: Array<{ voiceA: string; voiceB: string; key: string }> = [];
  for (let i = 0; i < voices.length; i++) {
    for (let j = i + 1; j < voices.length; j++) {
      const voiceA = voices[i]!;
      const voiceB = voices[j]!;
      pairs.push({
        voiceA,
        voiceB,
        key: sortedPairKey(voiceA, voiceB),
      });
    }
  }
  return pairs;
}

function PairingGrid({
  voices,
  ratings,
  previews,
  onScore,
  pendingKey,
  player,
}: {
  voices: string[];
  ratings: Map<string, PairRatingValue>;
  previews: VoicePreview[] | undefined;
  onScore: (
    voiceA: string,
    voiceB: string,
    rating: PairRatingValue | null
  ) => void;
  pendingKey: string | null;
  player: ReturnType<typeof usePreviewPlayer>;
}) {
  const [selected, setSelected] = useState<{
    voiceA: string;
    voiceB: string;
  } | null>(null);

  // Full grid: every same-gender pairing, including ones already scored.
  const pairings = useMemo(() => buildAllPairings(voices), [voices]);
  const scoredCount = useMemo(
    () => pairings.filter((pair) => ratings.has(pair.key)).length,
    [pairings, ratings]
  );

  // Ignore a stale selection when the gender filter no longer includes it.
  const activeSelection =
    selected &&
    voices.includes(selected.voiceA) &&
    voices.includes(selected.voiceB)
      ? selected
      : null;

  const selectedKey = activeSelection
    ? sortedPairKey(activeSelection.voiceA, activeSelection.voiceB)
    : null;
  const selectedRating = selectedKey
    ? (ratings.get(selectedKey) ?? null)
    : null;
  const selectedScore = scoreForRating(selectedRating);

  const playPair = (voiceA: string, voiceB: string) => {
    const previewA = previewFor(previews, voiceA);
    const previewB = previewFor(previews, voiceB);
    const key = sortedPairKey(voiceA, voiceB);

    if (!previewA || !previewB) {
      toast.error("Both voices need a preview clip to listen.");
      return;
    }

    if (player.playingPairKey === key) {
      player.stop();
      return;
    }

    const clip = (preview: VoicePreview, label: string) => ({
      url: `/api/tts/voice-previews/${preview.id}/audio`,
      label,
    });

    // A → B → A → B so operators hear them going back and forth.
    player.playSequence(
      [
        clip(previewA, voiceA),
        clip(previewB, voiceB),
        clip(previewA, voiceA),
        clip(previewB, voiceB),
      ],
      key
    );
  };

  if (voices.length < 2) {
    return (
      <p className="text-sm text-muted-foreground">
        Tag at least two voices with this gender to build a pairing grid.
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-muted-foreground">
        Every same-gender pairing is shown — including the{" "}
        {scoredCount > 0 ? `${scoredCount} already scored` : "ones you score"}{" "}
        — so you can re-score anytime. Tap a square to hear the voices alternate,
        then pick 1–4.
      </p>

      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
        {pairings.map(({ voiceA, voiceB, key }) => {
          const rating = ratings.get(key) ?? null;
          const score = scoreForRating(rating);
          const busy = pendingKey === key;
          const isSelected = selectedKey === key;
          const isPlaying = player.playingPairKey === key;
          const canListen = Boolean(
            previewFor(previews, voiceA) && previewFor(previews, voiceB)
          );
          return (
            <button
              key={key}
              type="button"
              disabled={busy}
              title={
                canListen
                  ? `${voiceA} × ${voiceB}: score ${score} (${rating ?? "unset"}) — tap to listen`
                  : `${voiceA} × ${voiceB}: score ${score} (${rating ?? "unset"}) — previews missing`
              }
              aria-label={`${voiceA} and ${voiceB} pair, score ${score}, ${rating ?? "unset"}`}
              aria-pressed={isSelected}
              className={cn(
                "relative flex aspect-square min-h-24 flex-col items-center justify-center gap-1 rounded-md border p-2 text-center transition-colors",
                rating
                  ? RATING_CLASS[rating]
                  : "bg-background hover:bg-muted text-muted-foreground",
                isSelected &&
                  "ring-2 ring-foreground/80 ring-offset-1 ring-offset-background",
                isPlaying && "animate-pulse"
              )}
              onClick={() => {
                setSelected({ voiceA, voiceB });
                if (canListen) {
                  playPair(voiceA, voiceB);
                }
              }}
            >
              {busy ? (
                <Loader2 className="size-4 animate-spin" />
              ) : isPlaying ? (
                <Pause className="size-4" />
              ) : (
                <span className="text-lg font-semibold tabular-nums leading-none">
                  {score === 1 ? "·" : score}
                </span>
              )}
              <span className="line-clamp-2 w-full text-[11px] font-medium leading-tight">
                {voiceA}
                <span className="mx-0.5 opacity-70">×</span>
                {voiceB}
              </span>
            </button>
          );
        })}
      </div>

      {activeSelection ? (
        <div className="flex flex-col gap-3 rounded-md border border-border/60 bg-muted/20 p-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="min-w-0">
            <p className="text-sm font-medium">
              {activeSelection.voiceA}{" "}
              <span className="text-muted-foreground">×</span>{" "}
              {activeSelection.voiceB}
            </p>
            <p className="text-xs text-muted-foreground">
              {player.playingPairKey === selectedKey
                ? `Playing ${player.playingVoice ?? "…"}…`
                : selectedRating
                  ? `Current score ${selectedScore} — ${PAIR_SCORES.find((o) => o.score === selectedScore)?.label} (tap a score to change)`
                  : "Listen, then pick a score"}
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={
                !previewFor(previews, activeSelection.voiceA) ||
                !previewFor(previews, activeSelection.voiceB)
              }
              onClick={() =>
                playPair(activeSelection.voiceA, activeSelection.voiceB)
              }
            >
              {player.playingPairKey === selectedKey ? (
                <>
                  <Pause className="size-3.5" />
                  Stop
                </>
              ) : (
                <>
                  <Play className="size-3.5" />
                  Replay A ↔ B
                </>
              )}
            </Button>
            <div
              className="flex items-center gap-1"
              role="group"
              aria-label="Pairing score"
            >
              {PAIR_SCORES.map((option) => {
                const active = selectedScore === option.score;
                return (
                  <button
                    key={option.score}
                    type="button"
                    title={`${option.score} — ${option.label}: ${option.hint}`}
                    aria-label={`Score ${option.score}, ${option.label}`}
                    aria-pressed={active}
                    disabled={pendingKey === selectedKey}
                    className={cn(
                      "flex size-9 items-center justify-center rounded-md border text-sm font-semibold tabular-nums transition-colors",
                      SCORE_BUTTON_CLASS[option.score],
                      active &&
                        "ring-2 ring-foreground/80 ring-offset-1 ring-offset-background"
                    )}
                    onClick={() =>
                      onScore(
                        activeSelection.voiceA,
                        activeSelection.voiceB,
                        ratingForScore(option.score)
                      )
                    }
                  >
                    {option.score}
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      ) : (
        <p className="text-sm text-muted-foreground">
          Select a square to listen and score that pairing.
        </p>
      )}

      <div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground">
        <span>Scores:</span>
        {PAIR_SCORES.map((option) => (
          <span
            key={option.score}
            className="inline-flex items-center gap-1.5"
          >
            <span
              className={cn(
                "inline-flex size-5 items-center justify-center rounded-sm border text-[10px] font-semibold",
                option.rating
                  ? RATING_CLASS[option.rating]
                  : "border-border/50 bg-background"
              )}
            >
              {option.score}
            </span>
            {option.label.toLowerCase()}
            {option.rating ? (
              <span className="opacity-60">({option.rating})</span>
            ) : null}
          </span>
        ))}
      </div>
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
            Voice pairings
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
          <PairingGrid
            voices={matrixVoices}
            ratings={ratingMap}
            previews={previewsQuery.data?.previews}
            pendingKey={pendingPairKey}
            player={player}
            onScore={(voiceA, voiceB, rating) =>
              pairMutation.mutate({ voiceA, voiceB, rating })
            }
          />
        </CardContent>
      </Card>
    </div>
  );
}
