"use client";

import { useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Play, Pause, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ttsApi } from "@/lib/tts/client";
import { OPENAI_VOICES } from "@/lib/tts/voices";
import { GEMINI_TTS_VOICES } from "@/lib/tts/gemini-voices";

const VOICES_BY_PROVIDER = {
  openai: OPENAI_VOICES,
  gemini: GEMINI_TTS_VOICES,
} as const;

const PROVIDER_LABEL: Record<keyof typeof VOICES_BY_PROVIDER, string> = {
  openai: "OpenAI",
  gemini: "Gemini",
};

export function VoiceSelect({
  provider,
  value,
  onChange,
  className,
}: {
  provider: keyof typeof VOICES_BY_PROVIDER;
  value: string;
  onChange: (value: string) => void;
  className?: string;
}) {
  const voices: readonly string[] = VOICES_BY_PROVIDER[provider];

  const { data } = useQuery({
    queryKey: ["voice-previews"],
    queryFn: () => ttsApi.listVoicePreviews(),
    staleTime: Infinity,
  });

  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [playingVoice, setPlayingVoice] = useState<string | null>(null);
  const [loadingVoice, setLoadingVoice] = useState<string | null>(null);

  const previewForVoice = (voice: string) =>
    data?.previews.find((p) => p.provider === provider && p.voice === voice);

  const handlePreview = (voice: string) => {
    const preview = previewForVoice(voice);
    if (!preview) return;

    if (playingVoice === voice) {
      audioRef.current?.pause();
      setPlayingVoice(null);
      return;
    }

    if (!audioRef.current) {
      audioRef.current = new Audio();
      audioRef.current.onended = () => setPlayingVoice(null);
      audioRef.current.onplay = () => setLoadingVoice(null);
    }
    audioRef.current.src = `/api/tts/voice-previews/${preview.id}/audio`;
    setLoadingVoice(voice);
    setPlayingVoice(voice);
    audioRef.current.play().catch(() => {
      setLoadingVoice(null);
      setPlayingVoice(null);
    });
  };

  const currentPreview = previewForVoice(value);

  return (
    <div className="flex items-center gap-2">
      <Select
        value={value}
        onValueChange={(v) => {
          if (v) onChange(v);
        }}
      >
        <SelectTrigger className={className ?? "w-full"}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectGroup>
            <SelectLabel>{PROVIDER_LABEL[provider]}</SelectLabel>
            {voices.map((v) => (
              <SelectItem key={v} value={v}>
                {v}
              </SelectItem>
            ))}
          </SelectGroup>
        </SelectContent>
      </Select>
      <Button
        type="button"
        variant="outline"
        size="icon"
        disabled={!currentPreview}
        onClick={() => handlePreview(value)}
        title={currentPreview ? `Preview ${value}` : "No preview available"}
      >
        {loadingVoice === value ? (
          <Loader2 className="size-4 animate-spin" />
        ) : playingVoice === value ? (
          <Pause className="size-4" />
        ) : (
          <Play className="size-4" />
        )}
      </Button>
    </div>
  );
}
