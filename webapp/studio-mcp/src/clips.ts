// Clip tools: the YouTube clip pipeline (Studio → Experiments → Clips), its
// Shorts queue, and the reports. Wraps /api/experiments/clip*, the public
// clip API the app reads, and the `pnpm clip:*` scripts in webapp/scripts.
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { StudioApiError, studioBaseUrl, studioFetch } from "./client.ts";
import {
  cancelJob,
  getJob,
  jobView,
  listJobs,
  runCommand,
  startJob,
  waitForJob,
  type JobContext,
} from "./jobs.ts";

const WEBAPP_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const BIN = (name: string) => path.join(WEBAPP_DIR, "node_modules", ".bin", name);

const STEPS = ["video-info", "transcribe", "tokenize", "align", "translate", "level", "tag", "feed"] as const;
type Step = (typeof STEPS)[number];
/** Steps whose route takes `{ model }`. */
const MODEL_STEPS = new Set<Step>(["transcribe", "translate", "level", "tag", "feed"]);
const STEP_MODELS = [
  "gemini-3.1-pro-preview",
  "gemini-3.8-flash",
  "gemini-3.5-flash-lite",
  "gemini-2.5-flash",
] as const;
const STEP_TIMEOUT_MS = 8 * 60_000;
const CLIP_ID = /^[a-z0-9-]+$/;
const YOUTUBE_ID = /^[A-Za-z0-9_-]{11}$/;

// --- Studio shapes (subset of webapp/lib/experiments/clips/types.ts) ------

type ClipToken = {
  text: string;
  reading?: string;
  startSec?: number;
  endSec?: number;
  score?: number;
  readingFallback?: boolean;
};
type ClipSentence = {
  text: string;
  tokens: ClipToken[] | null;
  score?: number;
  en?: string;
  flagsCleared?: boolean;
  basicSplit?: boolean;
};
type ClipDraft = {
  id: string;
  videoId: string;
  startSec: number;
  endSec: number;
  video?: { title: string; channelName: string; channelUrl?: string; thumbnailUrl?: string };
  orientation?: "landscape" | "portrait";
  durationSec: number;
  shiftSec: number;
  sentences: ClipSentence[];
  asr?: { model: string; at: string };
  translation?: { model: string; at: string };
  highlights?: unknown;
  alignment?: { alignerVersion: string; at: string };
  difficulty?: { jlptLevel: number; source: "auto" | "manual"; reason?: string; model?: string; at: string };
  deprecated?: { at: string; reason?: string };
  tags?: {
    auto?: { format: string; topics: string[]; register: string; speakers: string; dialect: string; series?: string; reason?: string; suggested?: string[]; model: string; at: string };
    manual?: { format: string; topics: string[]; register: string; speakers: string; dialect: string; series?: string; at: string };
  };
  feed?: {
    auto?: { eligible: boolean; reason?: string; model?: string; at: string };
    manual?: { eligible: boolean; at: string };
  };
  usage?: unknown[];
  createdAt: string;
  updatedAt: string;
};
type ClipSummary = {
  id: string;
  videoId: string;
  videoTitle: string | null;
  channelName: string | null;
  channelUrl: string | null;
  startSec: number;
  endSec: number;
  orientation: string;
  sentenceCount: number;
  tokenized: boolean;
  translated: boolean;
  highlighted: boolean;
  aligned: boolean;
  jlptLevel: number | null;
  deprecated: boolean;
  feed: "in" | "out" | "manual-in" | "manual-out" | "unchecked";
  feedReason: string | null;
  tags: { format: string; topics: string[]; register: string; speakers: string; dialect: string; series?: string } | null;
  tagsSource: "auto" | "manual" | null;
  pace: number | null;
  createdAt: string;
  updatedAt: string;
};
type ClipPendingInfo = {
  id: string;
  videoId: string;
  startSec: number;
  endSec: number | null;
  orientation: string;
  createdAt: string;
  expiresAt: string;
};
type ClipChecks = {
  id: string;
  feed: { state: string; eligible: boolean; reason: string | null };
  feedRules: Array<{ label: string; value: string; ok: boolean; problem: string }>;
  missingSteps: Step[];
  noSpeech: boolean;
  sentences: unknown[];
  counts: Record<string, number>;
  cost: { usd: number; floor: boolean; unpriced: boolean; byStep: Record<string, number> };
  [key: string]: unknown;
};
type ClipReport = {
  clips: ClipChecks[];
  missing: string[];
  totals: { needsLook: Record<string, string[]>; [key: string]: unknown };
};
/** Same as parseClipQueueDifficulties in webapp/lib/experiments/clips/queue.ts. */
const QUEUE_DIFFICULTIES = ["A1", "A2", "B1", "B2", "C1", "C2"];
const QUEUE_DIFFICULTY_GROUPS: Record<string, string[]> = {
  beginner: ["A1", "A2"],
  intermediate: ["B1"],
  advanced: ["B2", "C1", "C2"],
};
function parseClipQueueDifficulties(value: string): string[] {
  const levels = new Set<string>();
  for (const part of value.split(",").map((s) => s.trim()).filter(Boolean)) {
    const group = QUEUE_DIFFICULTY_GROUPS[part.toLowerCase()];
    if (group) group.forEach((l) => levels.add(l));
    else if (QUEUE_DIFFICULTIES.includes(part.toUpperCase())) levels.add(part.toUpperCase());
    else throw new Error(`Unknown difficulty "${part}": use beginner / intermediate / advanced or A1–C2.`);
  }
  if (levels.size === 0) throw new Error(`No difficulty in "${value}".`);
  return [...levels];
}

type QueueRow = {
  videoId: string;
  title: string;
  channelName: string;
  channelId: string | null;
  durationSec: number | null;
  source: string;
  status: "queued" | "skipped";
  note?: string;
  difficulty?: string;
  difficultyFrom?: "video" | "channel";
  flags: string[];
  progress: "none" | "fetching" | "clipped";
  clipIds: string[];
  channelDumpCount: number;
  addedAt: string;
  updatedAt: string;
};

// --- Helpers ----------------------------------------------------------------

function jsonResult(data: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
}

function errorResult(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return { isError: true, content: [{ type: "text" as const, text: message }] };
}

const round3 = (n: number | undefined) => (n === undefined ? undefined : Math.round(n * 1000) / 1000);

const getDraft = async (id: string) =>
  (await studioFetch<{ draft: ClipDraft; audioUrl: string }>(`/api/experiments/clips/${encodeURIComponent(id)}`));

async function clipReport(ids?: string[], since?: string): Promise<ClipReport> {
  const params = new URLSearchParams();
  if (ids?.length) params.set("ids", ids.join(","));
  if (since) params.set("since", since);
  const qs = params.toString();
  return studioFetch<ClipReport>(`/api/experiments/clip-report${qs ? `?${qs}` : ""}`, { timeoutMs: 120_000 });
}

const REPORT_MISSING =
  "Checks unavailable: this Studio has no /api/experiments/clip-report yet (deploy the webapp). The clip data itself is fine.";

/** clipReport, or null when the Studio at STUDIO_BASE_URL predates the report route. */
async function clipReportOrNull(ids: string[]): Promise<ClipReport | null> {
  try {
    return await clipReport(ids);
  } catch (error) {
    if (error instanceof StudioApiError && error.status === 404) return null;
    throw error;
  }
}

/** The compact per-clip verdict agents read after any change. */
function checksBrief(c: ClipChecks) {
  return {
    id: c.id,
    feed: c.feed,
    jlptLevel: c.jlptLevel,
    missingSteps: c.missingSteps,
    noSpeech: c.noSpeech,
    counts: c.counts,
    costUsd: Math.round(c.cost.usd * 10000) / 10000,
  };
}

/** `今日(きょう) | は | 暑い(あつい)`: readings only where they differ from the text. */
function tokenLine(tokens: ClipToken[] | null): string | null {
  if (!tokens) return null;
  return tokens.map((t) => (t.reading && t.reading !== t.text ? `${t.text}(${t.reading})` : t.text)).join(" | ");
}

function studioLink(id: string) {
  return `${studioBaseUrl()}/experiments/clips/${id}`;
}

/** Accepts a YouTube id or any watch / shorts / youtu.be / embed URL. */
function youtubeId(input: string): string {
  const trimmed = input.trim();
  if (YOUTUBE_ID.test(trimmed)) return trimmed;
  try {
    const url = new URL(trimmed);
    const v = url.searchParams.get("v");
    if (v && YOUTUBE_ID.test(v)) return v;
    const last = url.pathname.split("/").filter(Boolean).pop() ?? "";
    if (YOUTUBE_ID.test(last)) return last;
  } catch {
    // fall through
  }
  throw new Error(`Not a YouTube video id or link: ${input}`);
}

function webappScript(ctx: JobContext, script: string, args: string[], onLine?: (line: string) => void) {
  return runCommand(
    ctx,
    BIN("dotenv"),
    ["-e", ".env.local", "--", BIN("tsx"), path.join("scripts", script), ...args],
    { cwd: WEBAPP_DIR, env: { CLIP_STUDIO_URL: studioBaseUrl() }, onLine }
  );
}

// --- Pipeline steps (same rules as scripts/clip-queue-batch.ts) -------------

function missingSteps(d: ClipDraft): Step[] {
  const s = d.sentences;
  const tokenized = s.length > 0 && s.every((x) => x.tokens && x.tokens.length > 0);
  const aligned =
    tokenized && s.every((x) => (x.tokens ?? []).every((t) => t.startSec !== undefined && t.endSec !== undefined));
  const done: Record<Step, boolean> = {
    "video-info": Boolean(d.video),
    transcribe: s.length > 0 || Boolean(d.asr),
    tokenize: tokenized,
    align: aligned,
    translate: s.length > 0 && s.every((x) => Boolean(x.en?.trim())),
    level: Boolean(d.difficulty),
    tag: Boolean(d.tags?.auto || d.tags?.manual),
    feed: Boolean(d.feed?.auto || d.feed?.manual),
  };
  return STEPS.filter((step) => !done[step]);
}

type StepOptions = { model?: string; retokenize?: number[]; onlyUntimed?: boolean };

async function runStep(id: string, step: Step, draft: ClipDraft, options: StepOptions): Promise<ClipDraft> {
  const body: Record<string, unknown> = {};
  if (options.model && MODEL_STEPS.has(step)) body.model = options.model;
  if (step === "tokenize" && options.retokenize?.length) body.retokenize = options.retokenize;
  if (step === "align") {
    const partlyTimed = draft.sentences.some((s) => s.tokens?.some((t) => t.startSec !== undefined));
    if (options.onlyUntimed ?? partlyTimed) body.onlyUntimed = true;
  }
  const res = await studioFetch<{ draft: ClipDraft }>(
    `/api/experiments/clips/${encodeURIComponent(id)}/${step}`,
    { method: "POST", body: JSON.stringify(body), timeoutMs: STEP_TIMEOUT_MS }
  );
  return res.draft;
}

type ClipRunResult = { id: string; ran: Step[]; problems: string[]; stoppedEarly?: string };

async function processClip(
  ctx: JobContext,
  id: string,
  mode: "missing" | "steps",
  steps: Step[],
  options: StepOptions
): Promise<ClipRunResult> {
  const ran: Step[] = [];
  let problems: string[] = [];
  // Two rounds in "missing" mode: a step that timed out on our side usually
  // finished on the server, so look again before calling it a failure.
  const rounds = mode === "missing" ? 2 : 1;
  for (let round = 0; round < rounds; round++) {
    ctx.checkCancelled();
    let draft = (await getDraft(id)).draft;
    const todo = mode === "missing" ? missingSteps(draft) : steps;
    if (todo.length === 0) return { id, ran, problems: [] };
    if (draft.asr && draft.sentences.length === 0 && !todo.includes("transcribe")) {
      return { id, ran, problems: [], stoppedEarly: "no speech (transcript is empty)" };
    }
    problems = [];
    for (const step of todo) {
      ctx.checkCancelled();
      const started = Date.now();
      try {
        draft = await runStep(id, step, draft, options);
        ran.push(step);
        ctx.log(`${id}: ${step} ok (${Math.round((Date.now() - started) / 1000)} s)`);
        if (step === "transcribe" && draft.sentences.length === 0) {
          return { id, ran, problems: [], stoppedEarly: "no speech (transcript is empty)" };
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        problems.push(`${step}: ${message}`);
        ctx.log(`${id}: ${step} FAILED: ${message}`);
        // Later steps need tokens and timings.
        if (step === "transcribe" || step === "tokenize" || step === "align") break;
      }
    }
    if (problems.length === 0) break;
  }
  return { id, ran, problems };
}

async function processMany(
  ctx: JobContext,
  ids: string[],
  mode: "missing" | "steps",
  steps: Step[],
  options: StepOptions,
  concurrency: number
): Promise<ClipRunResult[]> {
  const results: ClipRunResult[] = [];
  let cursor = 0;
  const worker = async () => {
    while (cursor < ids.length && !ctx.isCancelled()) {
      const id = ids[cursor++]!;
      const result = await processClip(ctx, id, mode, steps, options).catch((error) => ({
        id,
        ran: [] as Step[],
        problems: [error instanceof Error ? error.message : String(error)],
      }));
      results.push(result);
      ctx.log(`[${results.length}/${ids.length}] ${id} ${result.problems.length ? "⚠ " + result.problems.join("; ") : "done"}`);
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(concurrency, ids.length)) }, worker));
  ctx.checkCancelled();
  return results;
}

/** Report on the clips a job touched, with any problems folded in. */
async function finishedClipsReport(ids: string[], runs?: ClipRunResult[]) {
  if (ids.length === 0) return { clips: [] };
  const report = await clipReportOrNull(ids);
  if (!report) {
    return {
      clips: (runs ?? ids.map((id) => ({ id }) as ClipRunResult)).map((r) => ({ ...r, studio: studioLink(r.id) })),
      note: REPORT_MISSING,
    };
  }
  const byId = new Map((runs ?? []).map((r) => [r.id, r]));
  const clips = report.clips.map((c) => ({
    ...checksBrief(c),
    ...(byId.has(c.id) ? { ran: byId.get(c.id)!.ran, problems: byId.get(c.id)!.problems } : {}),
    ...(byId.get(c.id)?.stoppedEarly ? { stoppedEarly: byId.get(c.id)!.stoppedEarly } : {}),
    studio: studioLink(c.id),
  }));
  const totalUsd = report.clips.reduce((n, c) => n + c.cost.usd, 0);
  return {
    clips,
    missing: report.missing,
    inFeed: report.clips.filter((c) => c.feed.eligible).length,
    totalCostUsd: Math.round(totalUsd * 10000) / 10000,
  };
}

// --- Shared schemas ---------------------------------------------------------

const stepSchema = z.enum(STEPS);
const waitSecondsSchema = (fallback: number) =>
  z
    .number()
    .int()
    .min(0)
    .max(55)
    .default(fallback)
    .describe(
      "Seconds to wait for the job before returning (≤55 to stay under host timeouts). It keeps running either way; poll get_clip_job."
    );

const grammarPatternSchema = z.union([
  z.string(),
  z.object({
    label: z.string().optional(),
    patternId: z.string().optional(),
    grammarPointID: z.string().optional(),
    sourceSpokenStart: z.number().int().nonnegative().optional(),
    sourceSpokenEnd: z.number().int().nonnegative().optional(),
  }),
]);

const highlightsSchema = z.object({
  vocabulary: z.array(z.string()).optional(),
  grammarPatterns: z
    .array(grammarPatternSchema)
    .optional()
    .describe("sourceSpokenStart/End are SENTENCE indices for clips."),
  contextNotes: z.array(z.string()).optional(),
});

// --- Tools ------------------------------------------------------------------

export function registerClipTools(server: McpServer) {
  // ---------------------------------------------------------------- reading

  server.registerTool(
    "list_clips",
    {
      title: "List clips",
      description:
        "List YouTube clips in Studio (Experiments → Clips), newest first, with pipeline state (tokenized / aligned / translated), JLPT level (5 = N5 … 1 = N1), catalog tags (format, topics, register, speakers, dialect, series) and pace (characters per second), feed verdict (in / out / manual-in / manual-out / unchecked) and why. Also returns clips still waiting for their audio (pending). Deprecated clips are left out unless deprecated is true or \"only\". Use get_clip for one clip's transcript and warnings, clip_report for warnings across clips.",
      inputSchema: {
        feed: z.enum(["in", "out", "manual-in", "manual-out", "unchecked", "eligible", "not-eligible"]).optional()
          .describe("eligible = in or manual-in; not-eligible = everything else."),
        level: z.number().int().min(1).max(5).optional().describe("Exact JLPT level (5 = N5 … 1 = N1)."),
        unrated: z.boolean().optional().describe("Only clips with no level."),
        format: z.string().optional().describe("Tag: anime, drama, comedy-skit, variety, vlog, streamer, explainer, how-to, interview, learner, other."),
        topic: z.string().optional().describe("Tag: food, travel, school, work, romance, family, friends, sports, games, health-fitness, money-shopping, tech, animals, history-culture, beauty-fashion, entertainment, daily-life."),
        untagged: z.boolean().optional().describe("Only clips with no catalog tags."),
        unfinished: z.boolean().optional().describe("Only clips missing a pipeline step (not aligned, translated, rated, tagged, video info, or feed verdict)."),
        channel: z.string().optional().describe("Case-insensitive substring of channel name or URL."),
        search: z.string().optional().describe("Case-insensitive substring of clip id, video id or title."),
        orientation: z.enum(["landscape", "portrait"]).optional(),
        deprecated: z.union([z.boolean(), z.literal("only")]).default(false),
        limit: z.number().int().min(1).max(500).default(50),
        offset: z.number().int().min(0).default(0),
      },
    },
    async (args) => {
      try {
        const { clips, pending } = await studioFetch<{ clips: ClipSummary[]; pending: ClipPendingInfo[] }>(
          "/api/experiments/clips"
        );
        const needle = (s: string | undefined) => s?.toLowerCase();
        const ch = needle(args.channel);
        const q = needle(args.search);
        const filtered = clips
          .filter((c) =>
            args.deprecated === "only" ? c.deprecated : args.deprecated === true ? true : !c.deprecated
          )
          .filter((c) => {
            if (!args.feed) return true;
            if (args.feed === "eligible") return c.feed === "in" || c.feed === "manual-in";
            if (args.feed === "not-eligible") return c.feed !== "in" && c.feed !== "manual-in";
            return c.feed === args.feed;
          })
          .filter((c) => args.level === undefined || c.jlptLevel === args.level)
          .filter((c) => !args.unrated || c.jlptLevel === null)
          .filter((c) => !args.format || c.tags?.format === args.format)
          .filter((c) => !args.topic || Boolean(c.tags?.topics.includes(args.topic)))
          .filter((c) => !args.untagged || c.tags === null)
          .filter(
            (c) =>
              !args.unfinished ||
              !c.aligned || !c.translated || c.jlptLevel === null || c.tags === null || c.videoTitle === null || c.feed === "unchecked"
          )
          .filter((c) => !ch || [c.channelName, c.channelUrl].some((v) => v?.toLowerCase().includes(ch)))
          .filter((c) => !q || [c.id, c.videoId, c.videoTitle].some((v) => v?.toLowerCase().includes(q)))
          .filter((c) => !args.orientation || c.orientation === args.orientation)
          .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
        const page = filtered.slice(args.offset, args.offset + args.limit).map((c) => ({
          id: c.id,
          videoId: c.videoId,
          title: c.videoTitle,
          channel: c.channelName,
          range: `${c.startSec.toFixed(1)}–${c.endSec.toFixed(1)} s`,
          orientation: c.orientation,
          lines: c.sentenceCount,
          state: [c.tokenized && "tokenized", c.aligned && "aligned", c.translated && "translated", c.highlighted && "highlighted"]
            .filter(Boolean)
            .join(", ") || "transcript only / empty",
          jlptLevel: c.jlptLevel,
          tags: c.tags,
          tagsSource: c.tagsSource,
          pace: c.pace,
          feed: c.feed,
          feedReason: c.feedReason,
          deprecated: c.deprecated,
          updatedAt: c.updatedAt,
        }));
        return jsonResult({
          total: filtered.length,
          offset: args.offset,
          clips: page,
          pending,
          studio: `${studioBaseUrl()}/experiments/clips`,
        });
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "get_clip",
    {
      title: "Get clip",
      description:
        "One clip: video, level, catalog tags, feed verdict and the measured feed rules, missing pipeline steps, cost, and the transcript. view \"review\" (default) shows each line as `index · Japanese · English · tokens` with tokens like `今日(きょう) | は` (reading only where it differs) and that line's warnings: low aligner score (< 0.3, worth a listen), reading fallback (reading guessed, check it), untimed tokens, basic split (phrase breaks fell back), missing English, flagsCleared (an editor marked it reviewed). view \"full\" adds every token's timing and score. Use sentenceFrom/sentenceTo for long clips.",
      inputSchema: {
        id: z.string().regex(CLIP_ID),
        view: z.enum(["review", "full"]).default("review"),
        sentenceFrom: z.number().int().min(0).optional(),
        sentenceTo: z.number().int().min(0).optional().describe("Inclusive."),
      },
    },
    async ({ id, view, sentenceFrom, sentenceTo }) => {
      try {
        const [{ draft, audioUrl }, report] = await Promise.all([getDraft(id), clipReportOrNull([id])]);
        const checks = report?.clips[0];
        const warnings = new Map(
          ((checks?.sentences ?? []) as Array<{ sentence: number } & Record<string, unknown>>).map((s) => [s.sentence, s])
        );
        const from = sentenceFrom ?? 0;
        const to = sentenceTo ?? draft.sentences.length - 1;
        const sentences = draft.sentences
          .map((s, i) => ({ s, i }))
          .filter(({ i }) => i >= from && i <= to)
          .map(({ s, i }) => {
            const w = warnings.get(i);
            const warn = w
              ? Object.fromEntries(
                  Object.entries(w).filter(
                    ([k, v]) =>
                      !["sentence", "text", "score"].includes(k) &&
                      v !== false && v !== 0 && !(Array.isArray(v) && v.length === 0)
                  )
                )
              : undefined;
            return {
              index: i,
              ja: s.text,
              en: s.en ?? null,
              tokens: tokenLine(s.tokens),
              score: round3(s.score) ?? null,
              ...(warn && Object.keys(warn).length ? { warnings: warn } : {}),
              ...(view === "full"
                ? {
                    tokenDetail: (s.tokens ?? []).map((t) => ({
                      text: t.text,
                      reading: t.reading,
                      startSec: round3(t.startSec),
                      endSec: round3(t.endSec),
                      score: round3(t.score),
                      ...(t.readingFallback ? { readingFallback: true } : {}),
                    })),
                  }
                : {}),
            };
          });
        return jsonResult({
          id: draft.id,
          videoId: draft.videoId,
          youtube: `https://www.youtube.com/watch?v=${draft.videoId}&t=${Math.floor(draft.startSec)}s`,
          video: draft.video ?? null,
          range: { startSec: draft.startSec, endSec: draft.endSec, durationSec: draft.durationSec },
          orientation: draft.orientation ?? "landscape",
          shiftSec: draft.shiftSec,
          asr: draft.asr ?? null,
          translation: draft.translation ?? null,
          alignment: draft.alignment ?? null,
          difficulty: draft.difficulty ?? null,
          tags: draft.tags ?? null,
          deprecated: draft.deprecated ?? null,
          feedStored: draft.feed ?? null,
          feed: checks?.feed,
          feedRules: checks?.feedRules.map(({ problem, ...rule }) => (rule.ok ? rule : { ...rule, problem })),
          missingSteps: checks?.missingSteps,
          counts: checks?.counts,
          cost: checks?.cost,
          highlights: draft.highlights ?? null,
          sentenceCount: draft.sentences.length,
          sentences,
          ...(report ? {} : { note: REPORT_MISSING }),
          audioUrl,
          studio: studioLink(id),
          updatedAt: draft.updatedAt,
        });
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "get_public_clip",
    {
      title: "Get public clip (what the app receives)",
      description:
        "The word-synced payload the iOS app fetches for a clip (/api/public/clips/:id), built live from the draft. 404 until every token is timed. Use it to tell bad data apart from an app rendering bug.",
      inputSchema: { id: z.string().regex(CLIP_ID) },
    },
    async ({ id }) => {
      try {
        return jsonResult(await studioFetch(`/api/public/clips/${encodeURIComponent(id)}`));
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "list_public_clips",
    {
      title: "List public clips (the app's list / feed)",
      description:
        "What the app's clip list or feed returns (/api/public/clips): aligned, non-deprecated clips. level = the learner's level (only clips at that level or easier; unrated left out). feed true = only feed clips. videoId = clips cut from one video. Tag filters (comma-separated values = any of; facets combine with and): format, topic, register (casual/polite/keigo), speakers (monologue/dialogue/group/narration), dialect (standard/kansai/other), pace (slow/natural/fast), series. q searches title, channel, first line and tag values. facets true returns the tag values in use with counts instead (/api/public/clips/facets). limit + cursor page it.",
      inputSchema: {
        level: z.number().int().min(1).max(5).optional(),
        feed: z.boolean().optional(),
        videoId: z.string().regex(YOUTUBE_ID).optional(),
        format: z.string().optional(),
        topic: z.string().optional(),
        register: z.string().optional(),
        speakers: z.string().optional(),
        dialect: z.string().optional(),
        pace: z.string().optional(),
        series: z.string().optional(),
        q: z.string().max(100).optional().describe("Text search: title, channel, first line or a tag value."),
        facets: z.boolean().optional(),
        limit: z.number().int().min(1).max(50).default(20),
        cursor: z.string().optional(),
      },
    },
    async ({ level, feed, videoId, limit, cursor, facets, ...tagFilters }) => {
      try {
        if (facets) return jsonResult(await studioFetch(`/api/public/clips/facets${feed ? "?feed=1" : ""}`));
        const params = new URLSearchParams();
        for (const [facet, value] of Object.entries(tagFilters)) if (value) params.set(facet, value);
        if (level !== undefined) params.set("level", String(level));
        if (feed) params.set("feed", "1");
        if (videoId) params.set("video_id", videoId);
        else params.set("limit", String(limit));
        if (cursor) params.set("cursor", cursor);
        return jsonResult(await studioFetch(`/api/public/clips?${params}`));
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "clip_report",
    {
      title: "Clip quality and cost report",
      description:
        "Across all clips (or ids): feed verdict counts, level distribution, why clips are out of the feed, missing steps, per-channel counts and cost, and needsLook: clip ids with unreviewed flagged lines, reading fallbacks, weak timing, basic splits, missing English, not aligned, no speech, unrated. Cost: estimated USD by step / model / day (audio runs are a floor; Align runs on our own aligner and costs nothing here). since limits cost to runs on or after a date. includeClips adds a per-clip summary.",
      inputSchema: {
        ids: z.array(z.string().regex(CLIP_ID)).max(200).optional(),
        since: z.string().optional().describe("YYYY-MM-DD; limits the cost totals."),
        includeClips: z.boolean().default(false),
        includeChannels: z.boolean().default(true),
        needsLookLimit: z
          .number()
          .int()
          .min(0)
          .max(500)
          .default(15)
          .describe("Max clip ids listed per needsLook bucket (counts are always complete)."),
      },
    },
    async ({ ids, since, includeClips, includeChannels, needsLookLimit }) => {
      try {
        const report = await clipReport(ids, since);
        const { channels, needsLook, ...totals } = report.totals as Record<string, unknown> & {
          needsLook: Record<string, string[]>;
        };
        return jsonResult({
          ...totals,
          needsLook: Object.fromEntries(
            Object.entries(needsLook).map(([k, list]) => [
              k,
              { count: list.length, ids: list.slice(0, needsLookLimit) },
            ])
          ),
          ...(includeChannels ? { channels } : {}),
          ...(report.missing.length ? { missingIds: report.missing } : {}),
          ...(includeClips ? { clips: report.clips.map(checksBrief) } : {}),
        });
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  // ---------------------------------------------------------------- editing

  server.registerTool(
    "patch_clip",
    {
      title: "Edit clip",
      description: [
        "Edit a clip draft (PATCH /api/experiments/clips/:id). Send only what changes. Fields are applied in this order: sentences, split, merge, english, tokens, clearFlags, highlights, jlptLevel, feedEligible, tags, deprecated, shiftSec, orientation.",
        "• sentences: the FULL transcript, one sentence per entry. Any change drops alignment and the automatic feed verdict (a hand-set feed answer stays); changed lines lose their tokens. Afterwards run run_clip_steps mode \"missing\" (tokenize → align → translate → level → tag → feed). Do not use this just to break or join subtitle lines.",
        "• split {sentence, atToken, english?}: break one line at token boundaries. atToken is the first token of the next line (1…n−1), or a list of those. Pieces join back to the original Japanese (punctuation between tokens stays on the left). Each token keeps its text, reading and timing; other lines, alignment and the feed verdict stay. english: one string per new line; omit or empty to fill in later. No tokenize or align needed.",
        "• merge {sentence, count?, english?}: join sentence with the next `count` lines (default 1). Tokens concatenate; timings, alignment and feed stay. english optional; omit to join existing English with a space.",
        "• english: one string per sentence, same count and order as the saved transcript (send sentences / split / merge first in the same call if the line count changes). Empty string clears a line.",
        "• tokens: hand-fix one sentence's tokens {sentence, tokens:[{text, reading?}]}. Token texts must join to exactly that sentence. Merges and reading fixes keep their timings; split halves need re-aligning (run_clip_steps steps [\"align\"], onlyUntimed).",
        "• clearFlags {sentence, cleared}: mark a line's warnings as reviewed.",
        "• highlights: replace vocabulary / grammarPatterns / contextNotes (grammar source indices are sentence indices); null clears.",
        "• jlptLevel 1–5 (5 = N5): hand-set level the Level step won't overwrite silently; null clears.",
        "• feedEligible: true = always in the feed, false = never; null = back to the automatic verdict.",
        "• tags {format, topics (0–3), register, speakers, dialect, series?}: hand-set catalog tags from the vocabulary (see list_clips filters; register casual/polite/keigo, speakers monologue/dialogue/group/narration, dialect standard/kansai/other). They win over the Tag step's and are never overwritten by it; null = back to the Tag step's.",
        "• deprecated {reason?}: retire a clip that has been live (hidden from lists, still served by id so saved items keep working); null restores. Prefer this to delete_clip.",
        "• shiftSec (−2…2): audio/video offset. orientation: portrait = 9:16 Short.",
      ].join("\n"),
      inputSchema: {
        id: z.string().regex(CLIP_ID),
        sentences: z.array(z.string()).max(200).optional(),
        split: z
          .object({
            sentence: z.number().int().min(0),
            atToken: z
              .union([
                z.number().int().min(1),
                z.array(z.number().int().min(1)).min(1).max(199),
              ])
              .describe("First token of the next line (1…n−1), or several of those. Punctuation between tokens stays on the left."),
            english: z
              .array(z.string().max(1000))
              .max(200)
              .optional()
              .describe("One string per new line. Omit or empty to fill in later."),
          })
          .optional(),
        merge: z
          .object({
            sentence: z.number().int().min(0),
            count: z.number().int().min(1).max(199).optional().describe("How many following lines to join in. Default 1."),
            english: z.string().max(1000).optional().describe("English for the joined line. Omit to join existing English with a space."),
          })
          .optional(),
        english: z.array(z.string().max(1000)).max(200).optional(),
        tokens: z
          .object({
            sentence: z.number().int().min(0),
            tokens: z.array(z.object({ text: z.string().min(1), reading: z.string().optional() })).min(1).max(300),
          })
          .optional(),
        clearFlags: z.object({ sentence: z.number().int().min(0), cleared: z.boolean() }).optional(),
        highlights: highlightsSchema.nullable().optional(),
        jlptLevel: z.number().int().min(1).max(5).nullable().optional(),
        feedEligible: z.boolean().nullable().optional(),
        tags: z
          .object({
            format: z.string(),
            topics: z.array(z.string()).max(3),
            register: z.string(),
            speakers: z.string(),
            dialect: z.string(),
            series: z.string().optional(),
          })
          .nullable()
          .optional(),
        deprecated: z.object({ reason: z.string().max(200).optional() }).nullable().optional(),
        shiftSec: z.number().min(-2).max(2).optional(),
        orientation: z.enum(["landscape", "portrait"]).optional(),
      },
    },
    async ({ id, ...patch }) => {
      try {
        const body = Object.fromEntries(Object.entries(patch).filter(([, v]) => v !== undefined));
        if (Object.keys(body).length === 0) throw new Error("Nothing to change.");
        await studioFetch(`/api/experiments/clips/${encodeURIComponent(id)}`, {
          method: "PATCH",
          body: JSON.stringify(body),
        });
        const report = await clipReportOrNull([id]);
        const checks = report?.clips[0];
        return jsonResult({
          id,
          changed: Object.keys(body),
          ...(report ? {} : { note: REPORT_MISSING }),
          ...(checks ? checksBrief(checks) : {}),
          ...(checks?.missingSteps.length
            ? { next: `Run run_clip_steps { ids: ["${id}"], mode: "missing" } to redo: ${checks.missingSteps.join(", ")}.` }
            : {}),
          studio: studioLink(id),
        });
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "delete_clip",
    {
      title: "Delete clip",
      description:
        "Permanently delete a clip (draft + audio) so its id can be reused, e.g. after a bad cut. Anything a learner saved from it stops resolving: for a clip that has been live, use patch_clip deprecated instead. Requires confirm: true.",
      inputSchema: { id: z.string().regex(CLIP_ID), confirm: z.literal(true) },
    },
    async ({ id }) => {
      try {
        await studioFetch(`/api/experiments/clips/${encodeURIComponent(id)}`, { method: "DELETE" });
        return jsonResult({ id, deleted: true });
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  // ---------------------------------------------------------------- pipeline

  server.registerTool(
    "run_clip_steps",
    {
      title: "Run clip pipeline steps",
      description: [
        "Run pipeline steps on one or more clips as a background job. Steps, in order: video-info (YouTube title/channel), transcribe (Gemini ASR; REPLACES the transcript, tokens, alignment and auto feed verdict), tokenize (words + readings), align (word timings), translate (English per line), level (JLPT estimate from text + pace), tag (catalog format / topics / register / speakers / dialect / series from title, channel and transcript; hand-set tags win), feed (measured rules, then Gemini judges coherence).",
        "mode \"missing\" (default) runs only what each clip lacks, in order, retrying once (like `pnpm clip:queue-batch --resume`). mode \"steps\" re-runs exactly `steps`, in pipeline order; after transcribe, also run tokenize/align/translate/level/tag/feed (or follow with mode \"missing\").",
        "model (transcribe/translate/level/tag/feed only) picks a Gemini model to compare. retokenize: sentence indices to re-tokenize (others keep their tokens). onlyUntimed: align only lines without timings (default when some lines are already timed).",
        "Returns a job; with waitSeconds it waits that long first. The result lists, per clip, steps run, problems and the new verdict / level / warnings.",
      ].join("\n"),
      inputSchema: {
        ids: z.array(z.string().regex(CLIP_ID)).min(1).max(100),
        mode: z.enum(["missing", "steps"]).default("missing"),
        steps: z.array(stepSchema).optional(),
        model: z.enum(STEP_MODELS).optional(),
        retokenize: z.array(z.number().int().min(0)).optional(),
        onlyUntimed: z.boolean().optional(),
        concurrency: z.number().int().min(1).max(8).default(3),
        waitSeconds: waitSecondsSchema(50),
      },
    },
    async ({ ids, mode, steps, model, retokenize, onlyUntimed, concurrency, waitSeconds }) => {
      try {
        if (mode === "steps" && !steps?.length) throw new Error('mode "steps" needs steps.');
        const ordered = mode === "steps" ? STEPS.filter((s) => steps!.includes(s)) : [];
        const uniqueIds = [...new Set(ids)];
        const job = startJob("steps", { ids: uniqueIds, mode, steps: ordered, model }, async (ctx) => {
          const runs = await processMany(ctx, uniqueIds, mode, ordered, { model, retokenize, onlyUntimed }, concurrency);
          return finishedClipsReport(uniqueIds, runs);
        });
        await waitForJob(job, waitSeconds);
        return jsonResult(jobView(job, 20));
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "get_clip_job",
    {
      title: "Get clip job",
      description:
        "Status, result and recent log lines of a clip job (run_clip_steps, create_clip_from_youtube, run_clip_queue_batch, seed_clip_queue, backfill_clip_index, compare_clip_asr). waitSeconds waits for it to finish first. Jobs live in this MCP server process; after a restart they are gone, but finished steps are saved in Studio (re-run run_clip_steps mode \"missing\").",
      inputSchema: {
        jobId: z.string(),
        waitSeconds: waitSecondsSchema(0),
        logLines: z.number().int().min(0).max(400).default(40),
      },
    },
    async ({ jobId, waitSeconds, logLines }) => {
      const job = getJob(jobId);
      if (!job) return errorResult(`No job ${jobId} (jobs are forgotten when the MCP server restarts).`);
      await waitForJob(job, waitSeconds);
      return jsonResult(jobView(job, logLines));
    }
  );

  server.registerTool(
    "list_clip_jobs",
    {
      title: "List clip jobs",
      description: "Clip jobs started in this MCP server session, newest first.",
      inputSchema: {},
    },
    async () => jsonResult(listJobs().map((j) => {
      const { result: _result, logTail: _log, ...rest } = jobView(j, 0);
      return rest;
    }))
  );

  server.registerTool(
    "cancel_clip_job",
    {
      title: "Cancel clip job",
      description:
        "Stop a running clip job. Step jobs stop before their next step (a step already sent to Studio still finishes there); script jobs get SIGTERM.",
      inputSchema: { jobId: z.string() },
    },
    async ({ jobId }) => {
      const job = cancelJob(jobId);
      if (!job) return errorResult(`No job ${jobId}.`);
      return jsonResult(jobView(job, 10));
    }
  );

  // ---------------------------------------------------------------- creating

  server.registerTool(
    "create_clip_from_youtube",
    {
      title: "Create clip from YouTube",
      description: [
        "Make a clip from a YouTube video range, end to end, as a background job: saves the clip details in Studio, downloads just that range on THIS machine (public/clip-fetch.mjs: yt-dlp + ffmpeg on PATH), uploads the audio, then (process, default true) runs every pipeline step.",
        "endSec null = to the end of the video. Audio over 120 s is split at pauses into <id>-01, <id>-02…; splitTargetSec (10–110) splits into clips of about that length even when shorter. portrait = 9:16 Short.",
        "id: lowercase letters, digits and dashes; must not exist. Queue Shorts use `short-<videoid lowercased>` (run_clip_queue_batch does this for you).",
      ].join("\n"),
      inputSchema: {
        id: z.string().regex(CLIP_ID).max(60),
        video: z.string().describe("YouTube video id or link (watch, shorts, youtu.be)."),
        startSec: z.number().min(0).default(0),
        endSec: z.number().positive().nullable().default(null),
        orientation: z.enum(["landscape", "portrait"]).default("landscape"),
        splitTargetSec: z.number().min(10).max(110).optional(),
        process: z.boolean().default(true),
        waitSeconds: waitSecondsSchema(0),
      },
    },
    async ({ id, video, startSec, endSec, orientation, splitTargetSec, process: andProcess, waitSeconds }) => {
      try {
        const videoId = youtubeId(video);
        // Save the details now so a bad id / range fails in the tool call itself.
        const { token } = await studioFetch<{ pending: ClipPendingInfo; token: string }>(
          "/api/experiments/clip-uploads",
          {
            method: "POST",
            body: JSON.stringify({ id, videoId, startSec, endSec, orientation, splitTargetSec: splitTargetSec ?? null }),
          }
        );
        const link = `${studioBaseUrl()}/hooks/clip-upload/${id}#${token}`;
        const job = startJob("create", { id, videoId, startSec, endSec, orientation, splitTargetSec }, async (ctx) => {
          ctx.log(`Fetching audio for ${id} (${videoId})…`);
          const code = await runCommand(ctx, process.execPath, [path.join(WEBAPP_DIR, "public", "clip-fetch.mjs"), link], {
            cwd: WEBAPP_DIR,
            onLine: (line) => {
              // yt-dlp progress is noise; keep what the script says.
              if (!/^\[download\]\s+\d/.test(line)) ctx.log(line);
            },
          });
          const { clips } = await studioFetch<{ clips: ClipSummary[] }>("/api/experiments/clips");
          const made = clips.map((c) => c.id).filter((c) => c === id || c.startsWith(`${id}-`)).sort();
          await studioFetch(`/api/experiments/clip-uploads/${id}`, { method: "DELETE" }).catch(() => undefined);
          if (made.length === 0) throw new Error(`No clip was created (fetch exited ${code}); see logTail.`);
          ctx.log(`Created ${made.join(", ")}`);
          if (!andProcess) return { created: made, studio: made.map(studioLink) };
          const runs = await processMany(ctx, made, "missing", [], {}, 3);
          return { created: made, ...(await finishedClipsReport(made, runs)) };
        });
        await waitForJob(job, waitSeconds);
        return jsonResult(jobView(job, 20));
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "discard_clip_pending",
    {
      title: "Discard pending clip upload",
      description:
        "Drop a clip whose details were saved but whose audio never arrived (listed under pending in list_clips), freeing its id.",
      inputSchema: { id: z.string().regex(CLIP_ID) },
    },
    async ({ id }) => {
      try {
        await studioFetch(`/api/experiments/clip-uploads/${encodeURIComponent(id)}`, { method: "DELETE" });
        return jsonResult({ id, discarded: true });
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  // ---------------------------------------------------------------- queue

  server.registerTool(
    "list_clip_queue",
    {
      title: "List clip queue",
      description:
        "The Shorts queue clips are made from, best first (no warnings, then channels the competitor used most, then shorter). Each row: status (queued / skipped, with note), progress (none / fetching / clipped, with clip ids), warnings (no duration, under 20 s, outside the feed's length, no Japanese in title, music/ASMR title), difficulty (soft CEFR hint from the local dump: the video's own, or its channel's usual level; absent = unknown). Default shows To do: queued, not yet clipped. Also returns counts, including To do by difficulty.",
      inputSchema: {
        difficulty: z
          .string()
          .optional()
          .describe('Only these levels: "beginner" (A1, A2), "intermediate" (B1), "advanced" (B2+), or levels like "A1,A2".'),
        status: z.enum(["queued", "skipped", "any"]).default("queued"),
        progress: z.enum(["none", "fetching", "clipped", "any"]).default("none"),
        flagged: z.boolean().optional().describe("true = only rows with warnings; false = only clean rows."),
        channel: z.string().optional().describe("Substring of channel name, or exact channel id."),
        search: z.string().optional().describe("Substring of title or video id."),
        limit: z.number().int().min(1).max(500).default(30),
        offset: z.number().int().min(0).default(0),
      },
    },
    async (args) => {
      try {
        const { rows, channels, updatedAt } = await studioFetch<{ rows: QueueRow[]; channels: number; updatedAt: string }>(
          "/api/experiments/clip-queue"
        );
        const ch = args.channel?.toLowerCase();
        const q = args.search?.toLowerCase();
        const levels = args.difficulty ? parseClipQueueDifficulties(args.difficulty) : null;
        const filtered = rows
          .filter((r) => !levels || (r.difficulty !== undefined && levels.includes(r.difficulty)))
          .filter((r) => args.status === "any" || r.status === args.status)
          .filter((r) => args.progress === "any" || r.progress === args.progress)
          .filter((r) => args.flagged === undefined || (r.flags.length > 0) === args.flagged)
          .filter((r) => !ch || r.channelName.toLowerCase().includes(ch) || (r.channelId ?? "").toLowerCase() === ch)
          .filter((r) => !q || r.title.toLowerCase().includes(q) || r.videoId.toLowerCase().includes(q));
        const count = (pred: (r: QueueRow) => boolean) => rows.filter(pred).length;
        const toDoByDifficulty: Record<string, number> = {};
        for (const r of rows) {
          if (r.status !== "queued" || r.progress !== "none") continue;
          const key = r.difficulty ?? "unknown";
          toDoByDifficulty[key] = (toDoByDifficulty[key] ?? 0) + 1;
        }
        return jsonResult({
          counts: {
            total: rows.length,
            toDo: count((r) => r.status === "queued" && r.progress === "none"),
            toDoClean: count((r) => r.status === "queued" && r.progress === "none" && r.flags.length === 0),
            fetching: count((r) => r.progress === "fetching"),
            clipped: count((r) => r.progress === "clipped"),
            skipped: count((r) => r.status === "skipped"),
            channels,
            toDoByDifficulty,
          },
          matched: filtered.length,
          rows: filtered.slice(args.offset, args.offset + args.limit).map((r) => ({
            videoId: r.videoId,
            title: r.title,
            channel: r.channelName,
            channelId: r.channelId,
            durationSec: r.durationSec,
            ...(r.difficulty ? { difficulty: r.difficulty, difficultyFrom: r.difficultyFrom } : {}),
            status: r.status,
            ...(r.note ? { note: r.note } : {}),
            progress: r.progress,
            ...(r.clipIds.length ? { clipIds: r.clipIds } : {}),
            ...(r.flags.length ? { flags: r.flags } : {}),
            channelDumpCount: r.channelDumpCount,
          })),
          updatedAt,
          studio: `${studioBaseUrl()}/experiments/clips/queue`,
        });
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "set_clip_queue_status",
    {
      title: "Skip / restore queue entries",
      description:
        "Set queue entries to skipped (with a note saying why, e.g. \"singing, no talk\") or back to queued. note \"\" clears it.",
      inputSchema: {
        videoIds: z.array(z.string().regex(YOUTUBE_ID)).min(1).max(500),
        status: z.enum(["queued", "skipped"]),
        note: z.string().max(500).optional(),
      },
    },
    async ({ videoIds, status, note }) => {
      try {
        return jsonResult(
          await studioFetch("/api/experiments/clip-queue", {
            method: "PATCH",
            body: JSON.stringify({ videoIds, status, ...(note !== undefined ? { note } : {}) }),
          })
        );
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "run_clip_queue_batch",
    {
      title: "Make a batch of clips from the queue",
      description: [
        "Runs `pnpm clip:queue-batch` as a background job: picks the next Shorts in To do (no warnings, one per channel, untried channels first), fetches their audio on this machine (yt-dlp + ffmpeg), runs every step, and reports level, feed verdict, timing and cost. Shorts whose audio can't be fetched are skipped in the queue.",
        "channel: take several from one channel instead (name substring or channel id; warnings don't hold them back, only length over 120 s; feed-length Shorts first). dryRun: only show the picks. resume: finish clips a stopped run left half-done (ignores count/channel/difficulty).",
        'difficulty: only Shorts with that soft difficulty hint: "beginner" (A1, A2), "intermediate" (B1), "advanced" (B2+), or levels like "A1,A2". Combines with channel. Shorts with no difficulty never match; the English-title warning doesn\'t hold them back. Run `pnpm clip:queue-difficulty <dump> --write` after adding Shorts so new ones get one.',
        "Takes minutes (about 1–2 min per clip at concurrency 5). Poll get_clip_job; the result has a structured report of the clips made.",
      ].join("\n"),
      inputSchema: {
        count: z.number().int().min(1).max(50).default(5),
        channel: z.string().optional(),
        difficulty: z.string().optional(),
        dryRun: z.boolean().default(false),
        resume: z.boolean().default(false),
        concurrency: z.number().int().min(1).max(8).default(5),
        waitSeconds: waitSecondsSchema(0),
      },
    },
    async ({ count, channel, difficulty, dryRun, resume, concurrency, waitSeconds }) => {
      try {
        // Fail here on a typo rather than inside the background job.
        if (difficulty) parseClipQueueDifficulties(difficulty);
        const args = resume
          ? ["--resume"]
          : [
              String(count),
              ...(channel ? ["--channel", channel] : []),
              ...(difficulty ? ["--difficulty", difficulty] : []),
              ...(dryRun ? ["--dry-run"] : []),
            ];
        args.push("--concurrency", String(concurrency));
        const job = startJob("batch", { count, channel, difficulty, dryRun, resume, concurrency }, async (ctx) => {
          const reported: string[] = [];
          const picked: string[] = [];
          const code = await webappScript(ctx, "clip-queue-batch.ts", args, (line) => {
            ctx.log(line);
            const r = /^(?:✅|❌|✗) (\S+?):?\s/.exec(line);
            if (r) reported.push(r[1]!);
            const p = /^\s{2}([A-Za-z0-9_-]{11})\s{2}/.exec(line);
            if (p) picked.push(p[1]!);
          });
          if (code !== 0) throw new Error(`clip-queue-batch exited ${code}; see logTail.`);
          if (dryRun) return { picked };
          return { picked, ...(await finishedClipsReport(reported)) };
        });
        await waitForJob(job, waitSeconds);
        return jsonResult(jobView(job, 30));
      } catch (error) {
        return errorResult(error);
      }
    }
  );

  server.registerTool(
    "seed_clip_queue",
    {
      title: "Seed the clip queue",
      description:
        "Runs `pnpm clip:queue-seed`: merges the Shorts from the competitor video dump (JSON) and the channel cache from fetch_video_info.py (JSONL) into the queue in R2. Dry run (stats only) unless write is true. Safe to re-run: existing entries keep their status and note. Talks to R2 directly with webapp/.env.local (the production bucket).",
      inputSchema: {
        dumpPath: z.string().describe("Absolute path to kiku-videos-dump.json."),
        cachePath: z.string().describe("Absolute path to videos-by-channel.cache.jsonl."),
        write: z.boolean().default(false),
        waitSeconds: waitSecondsSchema(30),
      },
    },
    async ({ dumpPath, cachePath, write, waitSeconds }) => {
      const job = startJob("seed", { dumpPath, cachePath, write }, async (ctx) => {
        const code = await webappScript(ctx, "clip-queue-seed.ts", [dumpPath, cachePath, ...(write ? ["--write"] : [])]);
        if (code !== 0) throw new Error(`clip-queue-seed exited ${code}; see logTail.`);
        return { exitCode: code, wrote: write };
      });
      await waitForJob(job, waitSeconds);
      return jsonResult(jobView(job, 60));
    }
  );

  server.registerTool(
    "backfill_clip_index",
    {
      title: "Rebuild the clip index",
      description:
        "Runs `pnpm clip:index-backfill`: rebuilds the Postgres clip_index (what the app's lists and feed read) from the drafts in R2. Needed after changing a feed rule threshold in lib/experiments/clips/feed.ts, since the index only picks up a new verdict when a clip is re-saved. Dry run (what would change) unless write is true. Uses webapp/.env.local (production R2 and database).",
      inputSchema: { write: z.boolean().default(false), waitSeconds: waitSecondsSchema(50) },
    },
    async ({ write, waitSeconds }) => {
      const job = startJob("backfill", { write }, async (ctx) => {
        const code = await webappScript(ctx, "clip-index-backfill.ts", write ? ["--write"] : []);
        if (code !== 0) throw new Error(`clip-index-backfill exited ${code}; see logTail.`);
        return { exitCode: code };
      });
      await waitForJob(job, waitSeconds);
      return jsonResult(jobView(job, 60));
    }
  );

  server.registerTool(
    "compare_clip_asr",
    {
      title: "Compare speech-to-text models on clips",
      description:
        [
          "Transcribes clips' stored audio with several models and shows where they disagree with the saved transcript and each other (lines every model agrees on are probably right; disagreements are what to listen to). Costs money per clip and model.",
          "Two ways to run: locally via `pnpm clip:asr-compare` (needs webapp/.env.local; ids or find, optionally within clip ids starting with prefix; models gemini-* go to Gemini, others to OpenAI), or on the Studio server (ids only; Gemini models from the step list, default gemini-3.1-pro-preview + gemini-3.8-flash).",
          "server: default true when STUDIO_BASE_URL isn't localhost (cloud agents have no .env.local). Server results list, per model, its lines and `vsSaved` stretches: `[x → ∅]` = the model didn't hear x, `[∅ → y]` = the saved transcript lacks y.",
        ].join("\n"),
      inputSchema: {
        ids: z.array(z.string().regex(CLIP_ID)).max(20).optional(),
        find: z.string().optional(),
        prefix: z.string().optional(),
        models: z.array(z.string()).optional(),
        server: z.boolean().optional(),
        waitSeconds: waitSecondsSchema(50),
      },
    },
    async ({ ids, find, prefix, models, server: onServer, waitSeconds }) => {
      if (!ids?.length && !find) return errorResult("Pass ids or find.");
      const useServer = onServer ?? !/^https?:\/\/(localhost|127\.0\.0\.1)(:|\/|$)/.test(studioBaseUrl());
      if (useServer) {
        if (!ids?.length) return errorResult("On the server, pass ids (find needs the local script).");
        const job = startJob("asr", { ids, models, server: true }, async (ctx) => {
          const results = [];
          for (const id of ids) {
            ctx.checkCancelled();
            ctx.log(`${id}: transcribing with ${models?.join(", ") ?? "default models"}…`);
            results.push(
              await studioFetch(`/api/experiments/clips/${encodeURIComponent(id)}/asr-compare`, {
                method: "POST",
                body: JSON.stringify(models?.length ? { models } : {}),
                timeoutMs: 300_000,
              })
            );
          }
          return results;
        });
        await waitForJob(job, waitSeconds);
        return jsonResult(jobView(job, 20));
      }
      const args = [
        ...(ids ?? []),
        ...(find ? ["--find", find] : []),
        ...(prefix ? ["--prefix", prefix] : []),
        ...(models?.length ? ["--models", models.join(",")] : []),
      ];
      const job = startJob("asr", { ids, find, prefix, models }, async (ctx) => {
        const code = await webappScript(ctx, "clip-asr-compare.ts", args);
        if (code !== 0) throw new Error(`clip-asr-compare exited ${code}; see logTail.`);
        return { exitCode: code };
      });
      await waitForJob(job, waitSeconds);
      return jsonResult(jobView(job, 300));
    }
  );
}
