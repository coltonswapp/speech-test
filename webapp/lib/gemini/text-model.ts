import "server-only";
import { GEMINI_TEXT_MODEL_DEFAULT } from "@/lib/gemini/models";

/**
 * The one Gemini text model Studio uses for generation, revision, grammar and
 * tokenize calls. Override with GEMINI_TEXT_MODEL (e.g. gemini-3.8-flash).
 */
export function geminiTextModel(): string {
  return process.env.GEMINI_TEXT_MODEL?.trim() || GEMINI_TEXT_MODEL_DEFAULT;
}

export type GeminiThinkingLevel = "minimal" | "low" | "medium" | "high";

export function geminiGenerateContentUrl(model: string): string {
  return `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
}
