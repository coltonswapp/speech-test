#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  autoStampTake,
  clearLessonThumbnail,
  clearSceneThumbnail,
  isUnpublished,
  scenarioSlug,
  setLessonThumbnail,
  setSceneThumbnail,
  studioBaseUrl,
  studioFetch,
  type CastVoiceEntry,
  type CollectionSummary,
  type DialogueCollection,
  isStageLine,
  type DialogueScenario,
  type ScenarioAudio,
  type TtsVariant,
  type UnitSummary,
} from "./client.ts";
import { analyzeScenario } from "./flags.ts";

function jsonResult(data: unknown) {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }],
  };
}

function errorResult(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return {
    isError: true,
    content: [{ type: "text" as const, text: message }],
  };
}

// Flat object so MCP hosts publish a JSON Schema the model can actually
// fill (z.union of stage/spoken often collapses to spoken-only).
const dialogueLineSchema = z.object({
  type: z.enum(["spoken", "stage"]).optional(),
  speaker: z.string().optional(),
  japanese: z.string().optional(),
  romaji: z.string().optional(),
  english: z.string().optional(),
  // Gemini TTS audio tags; Studio-only (not in public/iOS export).
  delivery: z.string().optional(),
  text: z.string().optional(),
  visibility: z.enum(["cold", "practice"]).optional(),
  id: z.string().optional(),
  grammarPointIDs: z.array(z.string()).optional(),
});

type PatchLineInput = z.infer<typeof dialogueLineSchema>;

function toPatchLine(line: PatchLineInput, index: number): Record<string, unknown> {
  if (line.type === "stage") {
    if (typeof line.text !== "string" || !line.text.trim()) {
      throw new Error(`lines[${index}]: stage rows require text`);
    }
    if (line.visibility !== "cold" && line.visibility !== "practice") {
      throw new Error(`lines[${index}]: stage rows require visibility "cold" or "practice"`);
    }
    return compact({
      type: "stage",
      text: line.text,
      visibility: line.visibility,
      id: line.id,
    });
  }
  if (typeof line.speaker !== "string") {
    throw new Error(`lines[${index}]: spoken rows require speaker`);
  }
  if (typeof line.japanese !== "string") {
    throw new Error(`lines[${index}]: spoken rows require japanese`);
  }
  return compact({
    type: line.type === "spoken" ? "spoken" : undefined,
    speaker: line.speaker,
    japanese: line.japanese,
    romaji: line.romaji,
    english: line.english,
    delivery:
      typeof line.delivery === "string" && line.delivery.trim()
        ? line.delivery.trim()
        : undefined,
    id: line.id,
    grammarPointIDs: line.grammarPointIDs,
  });
}

const grammarPatternSchema = z.union([
  z.string(),
  z.object({
    label: z.string(),
    grammarPointID: z.string().optional(),
  }),
]);

const highlightsSchema = z.object({
  vocabulary: z.array(z.string()).optional(),
  grammarPatterns: z.array(grammarPatternSchema).optional(),
  contextNotes: z.array(z.string()).optional(),
});

const quizQuestionSchema = z.object({
  prompt: z.string(),
  layout: z.enum(["grid", "list"]),
  choices: z.array(z.string()),
  correctChoice: z.string(),
  wrongAnswerExplanation: z.string(),
});

const castVoiceSchema = z.object({
  name: z.string().min(1),
  voice: z.string().min(1),
  provider: z.enum(["gemini", "openai"]).optional(),
});

/** Shared image args for thumbnail set tools. Prefer imageUrl when available. */
const thumbnailImageSchema = {
  imageUrl: z
    .string()
    .min(1)
    .optional()
    .describe("HTTP(S) URL of the image. Prefer this when the agent already has a URL."),
  imageBase64: z
    .string()
    .min(1)
    .optional()
    .describe(
      "Raw base64 image bytes, or a data URL (data:image/...;base64,...). Use when no URL is available."
    ),
  contentType: z
    .string()
    .min(1)
    .optional()
    .describe(
      "MIME type (image/jpeg|png|webp|gif). Required with raw imageBase64 unless the value is a data URL or filename has a known extension."
    ),
  filename: z
    .string()
    .min(1)
    .optional()
    .describe("Optional filename (e.g. cover.png). Used for MIME inference and the multipart file name."),
};

function compact<T extends Record<string, unknown>>(obj: T): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj)) {
    if (value !== undefined) out[key] = value;
  }
  return out;
}

const server = new McpServer({
  name: "shizen-studio",
  version: "0.1.0",
});

server.registerTool(
  "list_curriculum",
  {
    title: "List curriculum",
    description:
      "List Content Studio units, their collections, and scenario slugs/titles. Also includes unfiled collections (no unit). Marks unpublished scenarios.",
  },
  async () => {
    try {
      const [unitsRes, dialoguesRes] = await Promise.all([
        studioFetch<{ units: UnitSummary[] }>("/api/content/units"),
        studioFetch<{ collections: CollectionSummary[] }>("/api/content/dialogues"),
      ]);
      const collections = dialoguesRes.collections ?? [];
      const byId = new Map(collections.map((c) => [c.id, c]));

      const mapCollection = (id: string, fallbackTitle?: string) => {
        const col = byId.get(id);
        const title = col?.title ?? fallbackTitle ?? id;
        const scenarios = (col?.scenarios ?? []).map((scenario) => ({
          slug: scenarioSlug(scenario),
          title: scenario.menuTitle,
          unpublished: isUnpublished(scenario),
        }));
        return {
          id,
          title,
          subtitle: col?.subtitle ?? null,
          scenarios,
        };
      };

      const units = (unitsRes.units ?? []).map((unit) => ({
        id: unit.id,
        title: unit.title,
        subtitle: unit.subtitle,
        jlptLevel: unit.jlptLevel,
        orderIndex: unit.orderIndex,
        collections: (unit.collections ?? []).map((c) =>
          mapCollection(c.id, c.title)
        ),
      }));

      const filedIds = new Set(
        units.flatMap((u) => u.collections.map((c) => c.id))
      );
      const unfiledCollections = collections
        .filter((c) => !c.unitId || !filedIds.has(c.id))
        .map((c) => mapCollection(c.id));

      return jsonResult({
        studioBaseUrl: studioBaseUrl(),
        units,
        unfiledCollections,
      });
    } catch (error) {
      return errorResult(error);
    }
  }
);

server.registerTool(
  "get_scenario",
  {
    title: "Get scenario",
    description:
      "Load a scenario by collectionId + slug (2026-08-25 stage schema). Speakers, spoken rows (optional delivery Gemini TTS tags), and stage/ト書き rows as { type:\"stage\", text, visibility, role:\"stage\" }. Also B-line lengths, grammar tags, unpublished flag. Flags long B lines and a missing opener ト書き.",
    inputSchema: {
      collectionId: z.string().min(1),
      slug: z.string().min(1),
    },
  },
  async ({ collectionId, slug }) => {
    try {
      const { scenario } = await studioFetch<{ scenario: DialogueScenario }>(
        `/api/content/dialogues/${encodeURIComponent(collectionId)}/scenarios/${encodeURIComponent(slug)}`
      );
      const analysis = analyzeScenario(scenario.lines ?? []);
      const lines = (scenario.lines ?? []).map((line, index) => {
        const meta = analysis.lineMeta[index];
        if (isStageLine(line)) {
          return {
            index,
            type: "stage" as const,
            text: line.text,
            visibility: line.visibility,
            role: "stage" as const,
          };
        }
        return {
          index,
          type: "spoken" as const,
          speaker: line.speaker,
          role: meta.role,
          japanese: line.japanese,
          english: line.english ?? "",
          romaji: line.romaji ?? "",
          delivery: line.delivery ?? "",
          grammarPointIDs: line.grammarPointIDs ?? [],
          jpLength: meta.jpLength,
          togaki: meta.togaki,
          longB: meta.longB,
        };
      });
      const bLineLengths = lines.flatMap((line) => {
        if (line.type !== "spoken" || line.role !== "B") return [];
        return [
          {
            index: line.index,
            speaker: line.speaker,
            length: line.jpLength,
            japanese: line.japanese,
          },
        ];
      });

      return jsonResult({
        collectionId,
        slug,
        id: scenario.id,
        menuTitle: scenario.menuTitle,
        menuSubtitle: scenario.menuSubtitle,
        setting: scenario.setting,
        unpublished: isUnpublished(scenario),
        publishedAudioUrl: scenario.publishedAudioUrl,
        publishedAt: scenario.publishedAt,
        grammarTags: scenario.grammarPointIds ?? [],
        speakers: analysis.speakers,
        bSpeaker: analysis.bSpeaker,
        bLineLengths,
        flags: {
          missingTogaki: analysis.flags.missingTogaki,
          longBLines: analysis.flags.longBLines,
        },
        lines,
        highlights: scenario.highlights,
      });
    } catch (error) {
      return errorResult(error);
    }
  }
);

server.registerTool(
  "patch_scenario",
  {
    title: "Patch scenario",
    description:
      "Patch scenario lines and/or metadata via the existing Content Studio PATCH route. Only send fields to change. Each line is a flat object: spoken rows need speaker+japanese (optional delivery for Gemini TTS audio tags, e.g. \"[softly]\"); stage/ト書き rows need type:\"stage\", text, and visibility (cold|practice).",
    inputSchema: {
      collectionId: z.string().min(1),
      slug: z.string().min(1),
      menuTitle: z.string().min(1).optional(),
      menuSubtitle: z.string().nullable().optional(),
      japanese: z.string().optional(),
      romaji: z.string().optional(),
      english: z.string().optional(),
      targetSubstring: z.string().nullable().optional(),
      audioKey: z.string().nullable().optional(),
      grammarPointIds: z.array(z.string()).optional(),
      setting: z.string().nullable().optional(),
      lines: z.array(dialogueLineSchema).optional(),
      highlights: highlightsSchema.nullable().optional(),
      quiz: z.array(quizQuestionSchema).nullable().optional(),
    },
  },
  async (args) => {
    try {
      const { collectionId, slug, ...fields } = args;
      const body = compact(fields);
      if (Array.isArray(fields.lines)) {
        body.lines = fields.lines.map((line, index) => toPatchLine(line, index));
      }
      const { scenario } = await studioFetch<{ scenario: DialogueScenario }>(
        `/api/content/dialogues/${encodeURIComponent(collectionId)}/scenarios/${encodeURIComponent(slug)}`,
        { method: "PATCH", body: JSON.stringify(body) }
      );
      return jsonResult({ scenario });
    } catch (error) {
      return errorResult(error);
    }
  }
);

server.registerTool(
  "get_cast_voices",
  {
    title: "Get cast voices",
    description:
      "Read a collection castVoices registry (character name to Gemini/OpenAI voice, e.g. Kaito to Orus).",
    inputSchema: {
      collectionId: z.string().min(1),
    },
  },
  async ({ collectionId }) => {
    try {
      const { collection } = await studioFetch<{ collection: DialogueCollection }>(
        `/api/content/dialogues/${encodeURIComponent(collectionId)}`
      );
      return jsonResult({
        collectionId: collection.id,
        title: collection.title,
        castVoices: collection.castVoices ?? [],
      });
    } catch (error) {
      return errorResult(error);
    }
  }
);

server.registerTool(
  "set_cast_voices",
  {
    title: "Set cast voices",
    description:
      "Replace a collection castVoices registry. Provider defaults to gemini when omitted.",
    inputSchema: {
      collectionId: z.string().min(1),
      castVoices: z.array(castVoiceSchema),
    },
  },
  async ({ collectionId, castVoices }) => {
    try {
      const payload: CastVoiceEntry[] = castVoices.map((entry) => ({
        name: entry.name,
        voice: entry.voice,
        provider: entry.provider ?? "gemini",
      }));
      const { collection } = await studioFetch<{ collection: DialogueCollection }>(
        `/api/content/dialogues/${encodeURIComponent(collectionId)}`,
        {
          method: "PATCH",
          body: JSON.stringify({ castVoices: payload }),
        }
      );
      return jsonResult({
        collectionId: collection.id,
        title: collection.title,
        castVoices: collection.castVoices ?? [],
      });
    } catch (error) {
      return errorResult(error);
    }
  }
);

server.registerTool(
  "generate_take",
  {
    title: "Generate take",
    description:
      "Kick scenario audio generation: ensure the TTS project then POST a new variant take. Does not open waveform tools. Can take a minute or two.",
    inputSchema: {
      collectionId: z.string().min(1),
      slug: z.string().min(1),
      speaker1Voice: z.string().min(1).optional(),
      speaker2Voice: z.string().min(1).optional(),
    },
  },
  async ({ collectionId, slug, speaker1Voice, speaker2Voice }) => {
    try {
      const ensureBody = compact({ speaker1Voice, speaker2Voice });
      const audio = await studioFetch<ScenarioAudio>(
        `/api/content/dialogues/${encodeURIComponent(collectionId)}/scenarios/${encodeURIComponent(slug)}/audio`,
        {
          method: "POST",
          body: JSON.stringify(ensureBody),
          timeoutMs: 60_000,
        }
      );
      if (!audio.project?.id) {
        throw new Error("Failed to prepare the audio track.");
      }
      const generated = await studioFetch<{ variant: TtsVariant }>(
        `/api/tts/projects/${encodeURIComponent(audio.project.id)}/variants`,
        {
          method: "POST",
          body: JSON.stringify(ensureBody),
          timeoutMs: 180_000,
        }
      );
      return jsonResult({
        collectionId,
        slug,
        projectId: audio.project.id,
        variant: generated.variant,
        currentContentHash: audio.currentContentHash,
        speakerNames: audio.speakerNames,
      });
    } catch (error) {
      return errorResult(error);
    }
  }
);


server.registerTool(
  "auto_stamp_take",
  {
    title: "Auto-stamp take",
    description:
      "Forced-align a take: write token karaoke + derive line marks from audio (KA-3). Prefer after generate_take when the background job failed or you need a re-run. Pass force=true only to replace human/reviewed stamps; default refuses overwrite.",
    inputSchema: {
      projectId: z.string().min(1),
      variantId: z.string().min(1),
      force: z.boolean().optional(),
    },
  },
  async ({ projectId, variantId, force }) => {
    try {
      const result = await autoStampTake(projectId, variantId, {
        force: force === true,
      });
      return jsonResult({
        projectId,
        variantId,
        variant: result.variant,
        flags: result.flags,
        marksDerived: result.marksDerived,
        summary: result.summary,
      });
    } catch (error) {
      return errorResult(error);
    }
  }
);

server.registerTool(
  "set_lesson_thumbnail",
  {
    title: "Set lesson thumbnail",
    description:
      "Upload a lesson (collection) card thumbnail to CDN. JPEG/PNG/WebP/GIF ≤5MB. Provide imageUrl OR imageBase64 (+ contentType unless data URL / filename implies MIME). Prefers imageUrl when the agent has a URL. Sets thumbnailUrl and thumbnailSmallUrl on the collection.",
    inputSchema: {
      collectionId: z.string().min(1),
      ...thumbnailImageSchema,
    },
  },
  async ({ collectionId, imageUrl, imageBase64, contentType, filename }) => {
    try {
      const result = await setLessonThumbnail(collectionId, {
        imageUrl,
        imageBase64,
        contentType,
        filename,
      });
      return jsonResult({
        collectionId,
        thumbnailUrl: result.thumbnailUrl,
        thumbnailSmallUrl: result.thumbnailSmallUrl ?? null,
        collection: result.collection,
      });
    } catch (error) {
      return errorResult(error);
    }
  }
);

server.registerTool(
  "set_scene_thumbnail",
  {
    title: "Set scene thumbnail",
    description:
      "Upload a scene (scenario) thumbnail override to CDN. JPEG/PNG/WebP/GIF ≤5MB. Provide imageUrl OR imageBase64 (+ contentType unless data URL / filename implies MIME). Prefers imageUrl when the agent has a URL. Overrides the lesson thumbnail for this scene; clear_scene_thumbnail restores lesson fallback.",
    inputSchema: {
      collectionId: z.string().min(1),
      slug: z.string().min(1),
      ...thumbnailImageSchema,
    },
  },
  async ({ collectionId, slug, imageUrl, imageBase64, contentType, filename }) => {
    try {
      const result = await setSceneThumbnail(collectionId, slug, {
        imageUrl,
        imageBase64,
        contentType,
        filename,
      });
      return jsonResult({
        collectionId,
        slug,
        thumbnailUrl: result.thumbnailUrl,
        thumbnailSmallUrl: result.thumbnailSmallUrl ?? null,
        scenario: result.scenario,
      });
    } catch (error) {
      return errorResult(error);
    }
  }
);

server.registerTool(
  "clear_lesson_thumbnail",
  {
    title: "Clear lesson thumbnail",
    description:
      "Remove the lesson (collection) card thumbnail. Scenes that inherit the lesson thumbnail will also lose that image until a new lesson or scene thumbnail is set.",
    inputSchema: {
      collectionId: z.string().min(1),
    },
  },
  async ({ collectionId }) => {
    try {
      const { collection } = await clearLessonThumbnail(collectionId);
      return jsonResult({ collectionId, collection });
    } catch (error) {
      return errorResult(error);
    }
  }
);

server.registerTool(
  "clear_scene_thumbnail",
  {
    title: "Clear scene thumbnail",
    description:
      "Remove a scene (scenario) thumbnail override so the app falls back to the lesson (collection) thumbnail.",
    inputSchema: {
      collectionId: z.string().min(1),
      slug: z.string().min(1),
    },
  },
  async ({ collectionId, slug }) => {
    try {
      const { scenario } = await clearSceneThumbnail(collectionId, slug);
      return jsonResult({ collectionId, slug, scenario });
    } catch (error) {
      return errorResult(error);
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
