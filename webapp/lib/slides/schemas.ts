import { z } from "zod";
import {
  DECK_KINDS,
  DECK_STATUSES,
  EXPORT_SIZE_IDS,
  ITEM_SOURCES,
  RECIPE_IDS,
  SHOWCASE_KINDS,
} from "./types";

export const spotlightItemSchema = z.object({
  id: z.string().min(1),
  expression: z.string().min(1),
  reading: z.string(),
  gloss: z.string(),
  kind: z.enum(SHOWCASE_KINDS),
  source: z.enum(ITEM_SOURCES),
});

export const spotlightPayloadSchema = z.object({
  character: z.string().min(1),
  meanings: z.array(z.string()),
  onReadings: z.array(z.string()),
  kunReadings: z.array(z.string()),
  introTitle: z.string().min(1),
  badgeMeanings: z.array(z.string()).max(2),
  highlightColor: z.string().min(1),
  items: z.array(spotlightItemSchema),
  hashtags: z.array(z.string()).max(5),
});

export const decompositionCharacterSchema = z.object({
  character: z.string().min(1),
  meanings: z.array(z.string()),
  onReadings: z.array(z.string()),
  kunReadings: z.array(z.string()),
  badgeMeanings: z.array(z.string()).max(2),
});

export const decompositionPayloadSchema = z.object({
  expression: z.string().min(1),
  reading: z.string(),
  gloss: z.string(),
  glossOptions: z.array(z.string()),
  partLabel: z.string().min(1),
  definitionOverride: z.string().nullable(),
  characters: z.array(decompositionCharacterSchema).min(2).max(3),
  hashtags: z.array(z.string()).max(5),
});

export const deckPayloadSchema = z.union([
  spotlightPayloadSchema,
  decompositionPayloadSchema,
]);

export const patchDeckSchema = z.object({
  status: z.enum(DECK_STATUSES).optional(),
  recipeId: z.enum(RECIPE_IDS).optional(),
  exportSize: z.enum(EXPORT_SIZE_IDS).optional(),
  photoSet: z.string().min(1).optional(),
  photoSeed: z.number().int().optional(),
  payload: deckPayloadSchema.optional(),
});

export const createDeckSchema = z.object({
  kind: z.enum(DECK_KINDS),
  subject: z.string().min(1),
  recipeId: z.enum(RECIPE_IDS).optional(),
  exportSize: z.enum(EXPORT_SIZE_IDS).optional(),
  photoSet: z.string().min(1).optional(),
});

export const generateDeckSchema = z.object({
  kind: z.enum(DECK_KINDS).optional(),
});
