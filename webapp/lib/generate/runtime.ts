import "server-only";
import { alignerConfigured, alignVariantAudio } from "@/lib/aligner/client";
import { tokenizeJapaneseLines } from "@/lib/dialogue/gemini-tokenize";
import { deleteObject, getObject, putObject } from "@/lib/storage/r2";
import {
  encodeWavToMp3,
  transcodeToWavMono,
} from "@/lib/tts/audio-encode";
import {
  GEMINI_TTS_SAMPLE_RATE,
  synthesizeGeminiLine,
} from "@/lib/tts/gemini-tts";
import { drizzleGenerationStore } from "./db-store";
import type { GenerateService } from "./service";

export function studioGenerateService(): GenerateService {
  return {
    store: drizzleGenerationStore,
    objects: {
      put: putObject,
      get: getObject,
      delete: deleteObject,
    },
    tts: {
      synthesizeLine: synthesizeGeminiLine,
      sampleRate: GEMINI_TTS_SAMPLE_RATE,
    },
    encoder: {
      encodeWavToMp3,
      transcodeToWavMono,
    },
    aligner: {
      configured: alignerConfigured,
      align: alignVariantAudio,
    },
    tokenizer: {
      tokenize: tokenizeJapaneseLines,
    },
  };
}
