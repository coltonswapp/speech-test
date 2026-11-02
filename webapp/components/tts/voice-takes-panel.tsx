"use client";

import { useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Pause, Play } from "lucide-react";
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
import { VOICE_TAKES_MODEL } from "@/lib/tts/voice-takes";

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
 * from the R2 manifest written by scripts/seed-voice-takes.ts.
 */
export function VoiceTakesPanel() {
  const [gender, setGender] = useState(ALL);
  const [context, setContext] = useState(ALL);
  const [source, setSource] = useState(ALL);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState<string | null>(null);

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

  const rows = GEMINI_VOICE_CATALOG.filter(
    (v) =>
      (gender === ALL || v.gender === gender) &&
      (context === ALL || v.context === context) &&
      (source === ALL || v.source === source)
  );

  const toggle = (voice: string, take: number) => {
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
    audioRef.current.src = `/api/tts/voice-takes/audio?voice=${encodeURIComponent(voice)}&take=${take}`;
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
        {takesQuery.isLoading ? (
          <Skeleton className="h-48 w-full" />
        ) : !manifest ? (
          <p className="text-sm text-muted-foreground">
            No takes seeded yet. Run <code>pnpm db:seed-voice-takes</code> to
            generate and upload them.
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
                            <span className="text-xs text-muted-foreground">not seeded</span>
                          ) : (
                            takes.map((t) => {
                              const isPlaying = playing === `${v.voice}#${t.take}`;
                              return (
                                <Button
                                  key={t.take}
                                  type="button"
                                  size="sm"
                                  variant={isPlaying ? "default" : "outline"}
                                  onClick={() => toggle(v.voice, t.take)}
                                  title={`${v.displayName} take ${t.take} (${t.seconds}s)`}
                                >
                                  {isPlaying ? <Pause className="size-3" /> : <Play className="size-3" />}
                                  {t.take}
                                </Button>
                              );
                            })
                          )}
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
