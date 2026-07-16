import { z } from "zod";

export const ttsProviderSchema = z.enum(["openai", "elevenlabs", "gemini"]);
export type TTSProvider = z.infer<typeof ttsProviderSchema>;

export const compositionModeSchema = z.enum(["narration", "conversation"]);
export type CompositionMode = z.infer<typeof compositionModeSchema>;

export const dialogueLineSchema = z.object({
  speaker: z.enum(["speaker1", "speaker2"]),
  text: z.string(),
  orderIndex: z.number().int(),
});

export const createProjectSchema = z.object({
  promptText: z.string().default(""),
  instructions: z.string().nullable().optional(),
  provider: ttsProviderSchema.default("openai"),
  voice: z.string(),
  model: z.string(),
  compositionMode: compositionModeSchema.default("narration"),
  trackName: z.string().nullable().optional(),
});

export const updateProjectSchema = z.object({
  promptText: z.string().optional(),
  instructions: z.string().nullable().optional(),
  provider: ttsProviderSchema.optional(),
  voice: z.string().optional(),
  model: z.string().optional(),
  compositionMode: compositionModeSchema.optional(),
  trackName: z.string().nullable().optional(),
  speaker1Voice: z.string().nullable().optional(),
  speaker2Voice: z.string().nullable().optional(),
  speaker1Name: z.string().nullable().optional(),
  speaker2Name: z.string().nullable().optional(),
  selectedVariantId: z.string().uuid().nullable().optional(),
  dialogueLines: z
    .array(
      z.object({
        speaker: z.enum(["speaker1", "speaker2"]),
        text: z.string(),
      })
    )
    .optional(),
});
