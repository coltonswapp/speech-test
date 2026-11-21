// One-off speech audio for anything that needs a voice line (video
// automations, tests, demos): wraps Studio's Generate (POST /api/generate,
// Gemini TTS) and downloads the MP3s to disk. Unsaved generations expire from
// Studio after ~24 h; the downloaded files are yours to keep.
import { randomUUID } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { studioBaseUrl, studioFetch } from "./client.ts";

const MAX_TAKES = 5;
const DEFAULT_OUTPUT_DIR = path.join(os.tmpdir(), "shizen-audio");

type Generation = {
  id: string;
  title: string;
  model: string | null;
  durationSeconds: number;
  expiresAt: string | null;
  saved: boolean;
};

type VoiceEntry = {
  voice: string;
  displayName: string;
  source: "studio" | "library";
  languageCode: string;
  accent: string;
  gender: string;
  ageYears: number | null;
  pitch: string;
  persona: string;
  description: string;
};

function jsonResult(data: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
}

function errorResult(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return { isError: true, content: [{ type: "text" as const, text: message }] };
}

const LIB_TTS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../lib/tts");

let catalog: Promise<Array<VoiceEntry & { name: string }>> | null = null;

/** Studio's Gemini voice catalog (webapp/lib/tts), loaded at runtime so this package never type-checks the webapp. */
function voiceCatalog() {
  catalog ??= (async () => {
    const generated = (await import(pathToFileURL(path.join(LIB_TTS, "gemini-voice-catalog.generated.ts")).href)) as {
      GENERATED_GEMINI_VOICE_CATALOG: VoiceEntry[];
    };
    const names = (await import(pathToFileURL(path.join(LIB_TTS, "gemini-voice-names.ts")).href)) as {
      GEMINI_VOICE_CHARACTER_NAMES: Record<string, readonly [string, string]>;
    };
    return generated.GENERATED_GEMINI_VOICE_CATALOG.map((entry) => {
      const name = names.GEMINI_VOICE_CHARACTER_NAMES[entry.voice];
      return { ...entry, name: name ? `${name[0]} ${name[1]}` : entry.displayName };
    });
  })();
  return catalog;
}

/** Downloads a generation's MP3 (studioFetch reads text, so this is a raw fetch with the same auth). */
async function downloadMp3(id: string): Promise<Buffer> {
  const headers: Record<string, string> = {};
  const token = process.env.STUDIO_AGENT_TOKEN?.trim();
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${studioBaseUrl()}/api/generate/${encodeURIComponent(id)}/audio`, {
    headers,
    signal: AbortSignal.timeout(60_000),
  });
  if (!res.ok) throw new Error(`Downloading ${id} failed: HTTP ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}

/** Filesystem-safe stem from a title; empty for all-Japanese titles. */
function slug(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
}

function stamp(date = new Date()): string {
  return date.toISOString().replace(/[-:]/g, "").replace("T", "-").slice(0, 15);
}

export function registerAudioTools(server: McpServer) {
  server.registerTool(
    "generate_audio",
    {
      title: "Generate speech audio",
      description: [
        "Speak a line with Studio's Gemini TTS (Studio → Generate) and save the MP3 to disk. One take by default; takes (up to 5) gives independent renditions to pick from.",
        "voice: a Gemini voice id. ja-JP library voices (ja-jp-…, Tokyo accent, with age and persona) sound most natural for Japanese; the 30 prebuilt voices (Kore, Puck…) also speak Japanese. list_tts_voices to choose.",
        "delivery: how to say it, in plain words (\"Casual, like asking a friend a quick question\") or tags (\"[whispering]\", \"[laughs]\").",
        "language: optional and informational: Gemini reads the language from the text.",
        "Files go to outputDir (default: <tmp>/shizen-audio) as <stamp>-<title or voice>-take<n>.mp3. In Studio the generations stay ~24 h unless save: true keeps them in the Generate library.",
      ].join("\n"),
      inputSchema: {
        text: z.string().trim().min(1).max(4000),
        voice: z.string().min(1).max(120),
        delivery: z.string().max(200).optional(),
        language: z.string().max(20).optional(),
        takes: z.number().int().min(1).max(MAX_TAKES).default(1),
        title: z.string().max(150).optional(),
        save: z.boolean().default(false),
        outputDir: z.string().optional().describe("Absolute directory for the MP3s. Created if missing."),
      },
    },
    async ({ text, voice, delivery, language, takes, title, save, outputDir }) => {
      try {
        const voices = await voiceCatalog();
        const entry = voices.find((v) => v.voice === voice || v.voice.toLowerCase() === voice.toLowerCase());
        if (!entry) {
          const ja = voices.filter((v) => v.languageCode === "ja-JP").slice(0, 6).map((v) => `${v.voice} (${v.name})`);
          throw new Error(`Unknown voice “${voice}”. Try list_tts_voices; e.g. Kore, Puck, ${ja.join(", ")}.`);
        }
        const dir = path.resolve(outputDir ?? DEFAULT_OUTPUT_DIR);
        await mkdir(dir, { recursive: true });
        const baseTitle = title?.trim() || `${text.slice(0, 40)}${text.length > 40 ? "…" : ""}`;
        const stem = `${stamp()}-${slug(title ?? "") || slug(entry.voice)}`;

        const results = await Promise.all(
          Array.from({ length: takes }, async (_, i) => {
            const take = i + 1;
            try {
              const { generation } = await studioFetch<{ generation: Generation }>("/api/generate", {
                method: "POST",
                body: JSON.stringify({
                  title: takes > 1 ? `${baseTitle} · take ${take}` : baseTitle,
                  lines: [{ id: "line-1", text, voice: entry.voice, ...(delivery?.trim() ? { delivery: delivery.trim() } : {}) }],
                  requestId: randomUUID(),
                }),
                timeoutMs: 300_000,
              });
              if (save) {
                await studioFetch(`/api/generate/${encodeURIComponent(generation.id)}`, {
                  method: "PATCH",
                  body: JSON.stringify({ saved: true }),
                });
              }
              const mp3 = await downloadMp3(generation.id);
              const file = path.join(dir, `${stem}${takes > 1 ? `-take${take}` : ""}.mp3`);
              await writeFile(file, mp3);
              return {
                take,
                file,
                seconds: Math.round(generation.durationSeconds * 100) / 100,
                bytes: mp3.length,
                generationId: generation.id,
                model: generation.model,
                ...(save ? { saved: true } : { expiresAt: generation.expiresAt }),
              };
            } catch (error) {
              return { take, error: error instanceof Error ? error.message : String(error) };
            }
          })
        );

        const failed = results.filter((r) => "error" in r);
        if (failed.length === results.length) {
          return errorResult(`Every take failed: ${failed.map((r) => ("error" in r ? r.error : "")).join(" | ")}`);
        }
        return jsonResult({
          text,
          voice: `${entry.voice} (${entry.name}, ${entry.languageCode})`,
          ...(delivery ? { delivery } : {}),
          ...(language && !entry.languageCode.startsWith(language.slice(0, 2))
            ? { note: `${entry.voice} is a ${entry.languageCode} voice; Gemini still speaks the text's language.` }
            : {}),
          outputDir: dir,
          takes: results,
          studio: `${studioBaseUrl()}/generate`,
        });
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "list_tts_voices",
    {
      title: "List TTS voices",
      description:
        "Gemini voices generate_audio accepts: 73 ja-JP Tokyo-accent library voices (ja-jp-…, each with a Studio casting name, age, gender, pitch and persona) and 30 prebuilt multilingual voices (Kore, Puck…). Filter by language (e.g. ja-JP), gender, or search (matches name, persona, description).",
      inputSchema: {
        language: z.string().optional(),
        gender: z.enum(["female", "male", "neutral"]).optional(),
        search: z.string().optional(),
      },
    },
    async ({ language, gender, search }) => {
      try {
        const needle = search?.trim().toLowerCase();
        const voices = (await voiceCatalog()).filter(
          (v) =>
            (!language || v.languageCode.toLowerCase() === language.toLowerCase()) &&
            (!gender || v.gender === gender) &&
            (!needle ||
              [v.voice, v.name, v.persona, v.description].some((s) => s.toLowerCase().includes(needle)))
        );
        return jsonResult({
          count: voices.length,
          voices: voices.map((v) => ({
            voice: v.voice,
            name: v.name,
            language: v.languageCode,
            gender: v.gender,
            ...(v.ageYears ? { age: v.ageYears } : {}),
            pitch: v.pitch,
            persona: v.persona,
            description: v.description,
          })),
        });
      } catch (error) {
        return errorResult(error);
      }
    }
  );
}
