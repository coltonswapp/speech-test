"use client";

import { useMemo, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2, Pause, Play, RotateCcw, Sparkles, Square } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
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
import { ttsApi } from "@/lib/tts/client";
import { GEMINI_VOICE_CATALOG } from "@/lib/tts/gemini-voice-catalog";
import { VOICE_TAKES_MODEL, VOICE_TAKES_PER_VOICE } from "@/lib/tts/voice-takes";
import type { VoiceTakesBatchResult } from "@/lib/tts/voice-takes-batch";

/** Per-minute limits under this are waited out automatically. */
const AUTO_WAIT_MAX_SECONDS = 70;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** "Daily Gemini TTS limit reached, try again after ~1 AM MT" from the retry hint. */
export function quotaMessage(quota: NonNullable<VoiceTakesBatchResult["quota"]>, now = Date.now()) {
  if (!quota.daily && quota.retryAfterSeconds !== null) {
    return `Gemini TTS rate limit reached, try again in ~${Math.ceil(quota.retryAfterSeconds / 60)} min`;
  }
  // Daily quotas reset at midnight Pacific (~1 AM MT) when the API gives no hint.
  const at =
    quota.retryAfterSeconds !== null
      ? new Date(now + quota.retryAfterSeconds * 1000).toLocaleTimeString("en-US", {
          timeZone: "America/Denver",
          hour: "numeric",
        })
      : "1 AM";
  return `Daily Gemini TTS limit reached, try again after ~${at} MT`;
}

const ALL = "all";

function options(values: string[], allLabel: string) {
  return [
    { value: ALL, label: allLabel },
    ...[...new Set(values)].sort().map((v) => ({ value: v, label: v })),
  ];
}

const GENDER_ITEMS = options(GEMINI_VOICE_CATALOG.map((v) => v.gender), "All genders");
const CONTEXT_ITEMS = options(GEMINI_VOICE_CATALOG.map((v) => v.context), "All contexts");
const SOURCE_ITEMS = [
  { value: ALL, label: "All voices" },
  { value: "library", label: "ja-JP library (3.8 only)" },
  { value: "studio", label: "Studio 30" },
];

function FilterSelect({
  value,
  onChange,
  items,
}: {
  value: string;
  onChange: (value: string) => void;
  items: { value: string; label: string }[];
}) {
  return (
    <Select value={value} items={items} onValueChange={(v) => v && onChange(v)}>
      <SelectTrigger className="w-52">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectGroup>
          {items.map((item) => (
            <SelectItem key={item.value} value={item.value}>
              {item.label}
            </SelectItem>
          ))}
        </SelectGroup>
      </SelectContent>
    </Select>
  );
}

/**
 * Side-by-side listening: two takes of the same line per Gemini voice, read
 * from the R2 manifest. "Generate missing takes" loops small batches of
 * POST /api/tts/voice-takes/generate until done or a Gemini quota hit.
 */
export function VoiceTakesPanel() {
  const [gender, setGender] = useState(ALL);
  const [context, setContext] = useState(ALL);
  const [source, setSource] = useState(ALL);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState<string | null>(null);

  const queryClient = useQueryClient();
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [running, setRunning] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [regenerating, setRegenerating] = useState<string | null>(null);
  const stopRef = useRef(false);

  const applyBatch = (result: VoiceTakesBatchResult) => {
    queryClient.setQueryData(["voice-takes"], { manifest: result.manifest });
    setProgress({ done: result.doneVoices, total: result.totalVoices });
  };

  const generateMissing = async () => {
    stopRef.current = false;
    setRunning(true);
    setNotice(null);
    const failed = new Map<string, string>();
    let spent = 0;
    try {
      while (!stopRef.current) {
        const result = await ttsApi.generateVoiceTakes({ exclude: [...failed.keys()] });
        applyBatch(result);
        spent += result.costUSD;
        for (const f of result.failures) failed.set(f.voice, f.error);
        if (result.quota) {
          const wait = result.quota.retryAfterSeconds;
          if (!result.quota.daily && wait !== null && wait <= AUTO_WAIT_MAX_SECONDS) {
            setNotice(`Rate limited, resuming in ${wait}s…`);
            await sleep((wait + 1) * 1000);
            setNotice(null);
            continue;
          }
          setNotice(quotaMessage(result.quota));
          break;
        }
        if (result.remainingVoices - failed.size <= 0) {
          setNotice(
            failed.size
              ? `Done except ${failed.size} voice${failed.size === 1 ? "" : "s"} that failed: ${[...failed.keys()].join(", ")}`
              : "All voice takes generated."
          );
          break;
        }
      }
      if (stopRef.current) setNotice("Stopped. Progress is saved; run again to continue.");
    } catch (error) {
      setNotice((error as Error).message || "Could not generate voice takes.");
    } finally {
      setRunning(false);
      if (spent > 0) toast.success(`Voice takes: ~$${spent.toFixed(3)} of Gemini TTS this run`);
    }
  };

  const regenerate = async (voice: string) => {
    setRegenerating(voice);
    try {
      const result = await ttsApi.generateVoiceTakes({ voice, force: true });
      applyBatch(result);
      if (result.quota) toast.error(quotaMessage(result.quota));
      else if (result.failures.length) toast.error(`${voice}: ${result.failures[0].error}`);
      else toast.success(`Regenerated ${voice}`);
    } catch (error) {
      toast.error((error as Error).message);
    } finally {
      setRegenerating(null);
    }
  };

  const takesQuery = useQuery({
    queryKey: ["voice-takes"],
    queryFn: () => ttsApi.getVoiceTakes(),
    staleTime: Infinity,
  });
  const manifest = takesQuery.data?.manifest ?? null;
  const takesByVoice = useMemo(
    () => new Map((manifest?.voices ?? []).map((v) => [v.voice, v.takes])),
    [manifest]
  );

  const completeVoices = GEMINI_VOICE_CATALOG.filter(
    (v) => (takesByVoice.get(v.voice)?.length ?? 0) >= VOICE_TAKES_PER_VOICE
  ).length;
  const shown = progress ?? { done: completeVoices, total: GEMINI_VOICE_CATALOG.length };

  const rows = GEMINI_VOICE_CATALOG.filter(
    (v) =>
      (gender === ALL || v.gender === gender) &&
      (context === ALL || v.context === context) &&
      (source === ALL || v.source === source)
  );

  const toggle = (voice: string, take: number, sha: string) => {
    const id = `${voice}#${take}`;
    if (!audioRef.current) {
      audioRef.current = new Audio();
      audioRef.current.onended = () => setPlaying(null);
    }
    if (playing === id) {
      audioRef.current.pause();
      setPlaying(null);
      return;
    }
    audioRef.current.src = `/api/tts/voice-takes/audio?voice=${encodeURIComponent(voice)}&take=${take}&v=${sha.slice(0, 12)}`;
    setPlaying(id);
    audioRef.current.play().catch(() => setPlaying(null));
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base font-medium">Voice takes</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <p className="text-sm text-muted-foreground">
          Two takes of the same line per voice on {VOICE_TAKES_MODEL}
          {manifest ? <> — “{manifest.sampleText}”</> : null}. Library voices only
          work with 3.8 TTS models.
        </p>
        <div className="flex flex-wrap gap-2">
          <FilterSelect value={source} onChange={setSource} items={SOURCE_ITEMS} />
          <FilterSelect value={gender} onChange={setGender} items={GENDER_ITEMS} />
          <FilterSelect value={context} onChange={setContext} items={CONTEXT_ITEMS} />
          <span className="self-center text-xs text-muted-foreground">
            {rows.length} voice{rows.length === 1 ? "" : "s"}
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {running ? (
            <Button type="button" size="sm" variant="outline" onClick={() => (stopRef.current = true)}>
              <Square className="size-3" />
              Stop
            </Button>
          ) : (
            <Button
              type="button"
              size="sm"
              onClick={generateMissing}
              disabled={takesQuery.isLoading || shown.done >= shown.total}
            >
              <Sparkles className="size-3" />
              Generate missing takes
            </Button>
          )}
          <span className="text-xs text-muted-foreground">
            {running && <Loader2 className="mr-1 inline size-3 animate-spin" />}
            {shown.done}/{shown.total} voices have {VOICE_TAKES_PER_VOICE} takes
          </span>
          {notice && <span className="text-xs text-amber-600 dark:text-amber-400">{notice}</span>}
        </div>
        {takesQuery.isLoading ? (
          <Skeleton className="h-48 w-full" />
        ) : !manifest ? (
          <p className="text-sm text-muted-foreground">
            No takes yet. Click <strong>Generate missing takes</strong> to
            create them ({GEMINI_VOICE_CATALOG.length * VOICE_TAKES_PER_VOICE} takes,
            about $0.30 of Gemini TTS).
          </p>
        ) : (
          <div className="overflow-x-auto rounded-md border">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs text-muted-foreground">
                <tr>
                  <th className="px-3 py-2">Voice</th>
                  <th className="px-3 py-2">Takes</th>
                  <th className="px-3 py-2">Who</th>
                  <th className="px-3 py-2">Context / persona</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((v) => {
                  const takes = takesByVoice.get(v.voice) ?? [];
                  return (
                    <tr key={v.voice} className="border-t align-top">
                      <td className="px-3 py-2">
                        <div className="font-medium">{v.displayName}</div>
                        <div className="text-xs text-muted-foreground">{v.voice}</div>
                        {v.source === "library" && (
                          <Badge variant="outline" className="mt-1">
                            3.8 only
                          </Badge>
                        )}
                      </td>
                      <td className="px-3 py-2">
                        <div className="flex gap-1">
                          {takes.length === 0 ? (
                            <span className="text-xs text-muted-foreground">not generated</span>
                          ) : (
                            takes.map((t) => {
                              const isPlaying = playing === `${v.voice}#${t.take}`;
                              return (
                                <Button
                                  key={t.take}
                                  type="button"
                                  size="sm"
                                  variant={isPlaying ? "default" : "outline"}
                                  onClick={() => toggle(v.voice, t.take, t.sha256)}
                                  title={`${v.displayName} take ${t.take} (${t.seconds}s)`}
                                >
                                  {isPlaying ? <Pause className="size-3" /> : <Play className="size-3" />}
                                  {t.take}
                                </Button>
                              );
                            })
                          )}
                          <Button
                            type="button"
                            size="sm"
                            variant="ghost"
                            onClick={() => regenerate(v.voice)}
                            disabled={running || regenerating !== null}
                            title={`Regenerate ${v.displayName}'s takes`}
                            aria-label={`Regenerate ${v.displayName}'s takes`}
                          >
                            {regenerating === v.voice ? (
                              <Loader2 className="size-3 animate-spin" />
                            ) : (
                              <RotateCcw className="size-3" />
                            )}
                          </Button>
                        </div>
                      </td>
                      <td className="px-3 py-2 text-xs">
                        {v.gender}
                        {v.ageYears ? `, ${v.ageYears}` : ""}, {v.pitch} pitch
                        <div className="text-muted-foreground">{v.accent}</div>
                      </td>
                      <td className="px-3 py-2 text-xs">
                        <div>{v.context}</div>
                        <div className="text-muted-foreground">{v.persona}</div>
                        <div className="mt-1 max-w-md text-muted-foreground">{v.description}</div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
