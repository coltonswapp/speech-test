// Tokenize model comparison: runs candidate models on lines from listed clips
// with the production prompt and checks, and compares them with the tokens the
// clips carry now. Saves nothing to clips or the line cache.
//
//   pnpm clip:tokenize-compare                         # 150 lines, default models
//   pnpm clip:tokenize-compare --lines 300 --seed 2
//   pnpm clip:tokenize-compare --models gemini:gemini-3.8-flash,openrouter:openai/gpt-6-luna@minimal
//   pnpm clip:tokenize-compare --clips short-abc,short-def --out ./tok-run
//
// Models: `gemini:<model>` (Gemini API, GEMINI_API_KEY, like production) or
// `openrouter:<slug>` (OPENROUTER_API_KEY). `@<effort>` sets reasoning
// (minimal|low|medium|high|none); default low, as production.
//
// No answer key exists for most lines, so read the numbers this way:
// - ok / retry / failed: whether the tokens spell out the line (validatedTokens),
//   first try or after production's retry prompt. Objective.
// - vs current: agreement with the clip's tokens today (3.8 Flash, plus any
//   hand fixes). Run 3.8 Flash itself as a model to see its own run-to-run
//   agreement: a candidate near that line is as good as we can tell here.
// - vs hand fixes: lines whose tokens differ from the line cache were corrected
//   in Studio; the closest thing to an answer key.
// - The diff report (diff.md) lists every disagreement, for a person to judge.
import { mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GetObjectCommand, ListObjectsV2Command, S3Client } from "@aws-sdk/client-s3";
import { inArray } from "drizzle-orm";
import { db } from "../lib/db/standalone-client";
import { appSettings } from "../lib/db/schema";
import { buildTokenizePrompt } from "../lib/dialogue/tokenize-prompt";
import { tokenizeCacheKey, tokensWithReadings, type RawToken } from "../lib/dialogue/token-readings";
import { estimateGeminiCostUSD } from "../lib/gemini/models";
import { clipDraftSchema, clipIsAligned, type ClipDraft } from "../lib/experiments/clips/types";

const ROOT = "experiments/clips/";
const DEFAULT_MODELS = [
  "gemini:gemini-3.8-flash",
  "openrouter:deepseek/deepseek-v4.1-flash-1017",
  "openrouter:openai/gpt-6-luna",
];
const CONCURRENCY = 4;
const SEED = 42; // production's tokenize seed

const args = process.argv.slice(2);
const option = (name: string) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};

function env(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name} in .env.local`);
  return value;
}

const s3 = new S3Client({
  region: "auto",
  endpoint: process.env.R2_ENDPOINT?.trim() || `https://${env("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com`,
  credentials: { accessKeyId: env("R2_ACCESS_KEY_ID"), secretAccessKey: env("R2_SECRET_ACCESS_KEY") },
});
const bucket = env("R2_BUCKET_NAME");

async function listDraftIds(): Promise<string[]> {
  const ids: string[] = [];
  let token: string | undefined;
  do {
    const out = await s3.send(
      new ListObjectsV2Command({ Bucket: bucket, Prefix: ROOT, Delimiter: "/", ContinuationToken: token })
    );
    for (const p of out.CommonPrefixes ?? []) {
      const id = p.Prefix?.slice(ROOT.length).replace(/\/$/, "");
      if (id) ids.push(id);
    }
    token = out.IsTruncated ? out.NextContinuationToken : undefined;
  } while (token);
  return ids;
}

async function readDraft(id: string): Promise<ClipDraft | null> {
  try {
    const out = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: `${ROOT}${id}/draft.json` }));
    const parsed = clipDraftSchema.safeParse(JSON.parse(await out.Body!.transformToString("utf8")));
    return parsed.success ? parsed.data : null;
  } catch (error) {
    if ((error as { name?: string }).name === "NoSuchKey") return null;
    throw error;
  }
}

// ── Lines ────────────────────────────────────────────────────────────────

type Tok = { text: string; reading?: string };
type Line = {
  clipId: string;
  index: number;
  text: string;
  current: Tok[];
  /** The clip's tokens differ from the line cache: corrected by hand in Studio. */
  handFixed: boolean;
  tags: string[];
};

const JAPANESE = /[぀-ヿ㐀-䶿一-鿿]/;

function lineTags(text: string): string[] {
  const tags: string[] = [];
  if (/[0-9０-９]/.test(text)) tags.push("digits");
  if (/っ(て|た|ちゃ)|ちゃ|じゃ|てる|でる|とく|どく/.test(text)) tags.push("contraction");
  if (/ん(です|だ)/.test(text)) tags.push("n-desu");
  if (text.length > 30) tags.push("long");
  return tags;
}

/** Deterministic shuffle (mulberry32), so a seed always picks the same lines. */
function shuffled<T>(items: T[], seed: number): T[] {
  let a = seed >>> 0;
  const rand = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

const sameTokens = (a: Tok[], b: Tok[]) =>
  a.length === b.length && a.every((t, i) => t.text === b[i].text && (t.reading ?? "") === (b[i].reading ?? ""));

async function loadLines(clipIds: string[] | undefined, count: number, seed: number) {
  const ids = clipIds ?? (await listDraftIds());
  const drafts: ClipDraft[] = [];
  for (let i = 0; i < ids.length; i += 20) {
    const batch = await Promise.all(ids.slice(i, i + 20).map(readDraft));
    drafts.push(...batch.filter((d): d is ClipDraft => d !== null));
  }
  const listed = drafts.filter((d) => clipIsAligned(d) && !d.deprecated);
  const seen = new Set<string>();
  const all: Omit<Line, "handFixed">[] = [];
  for (const d of listed) {
    d.sentences.forEach((s, index) => {
      const text = s.text.trim();
      if (!s.tokens?.length || s.basicSplit || !JAPANESE.test(text) || seen.has(text)) return;
      seen.add(text);
      all.push({
        clipId: d.id,
        index,
        text,
        current: s.tokens.map((t) => ({ text: t.text, ...(t.reading ? { reading: t.reading } : {}) })),
        tags: lineTags(text),
      });
    });
  }
  const picked = clipIds ? all : shuffled(all, seed).slice(0, count);

  // The line cache holds the model's own answer per line text.
  const keys = picked.map((l) => tokenizeCacheKey(l.text));
  const cached = new Map<string, Tok[]>();
  for (let i = 0; i < keys.length; i += 200) {
    const rows = await db
      .select({ key: appSettings.key, value: appSettings.value })
      .from(appSettings)
      .where(inArray(appSettings.key, keys.slice(i, i + 200)));
    for (const r of rows) cached.set(r.key, ((r.value as { tokens?: Tok[] })?.tokens ?? []) as Tok[]);
  }
  const lines: Line[] = picked.map((l) => {
    const fromCache = cached.get(tokenizeCacheKey(l.text));
    return { ...l, handFixed: Boolean(fromCache && !sameTokens(fromCache, l.current)) };
  });
  const sentencesPerClip = listed.reduce((n, d) => n + d.sentences.length, 0) / Math.max(1, listed.length);
  return { lines, pool: all.length, sentencesPerClip };
}

// ── Models ───────────────────────────────────────────────────────────────

type Effort = "minimal" | "low" | "medium" | "high" | "none";
type ModelSpec = { label: string; provider: "gemini" | "openrouter"; model: string; effort: Effort };

function parseModel(spec: string): ModelSpec {
  const [base, effort = "low"] = spec.split("@");
  const colon = base.indexOf(":");
  const provider = base.slice(0, colon);
  const model = base.slice(colon + 1);
  if ((provider !== "gemini" && provider !== "openrouter") || !model) {
    throw new Error(`Model "${spec}": use gemini:<model> or openrouter:<slug>[@effort].`);
  }
  if (!["minimal", "low", "medium", "high", "none"].includes(effort)) throw new Error(`Unknown effort in "${spec}".`);
  return { label: spec, provider, model, effort: effort as Effort };
}

type CallResult = {
  raw: RawToken[] | null;
  /** Why raw is null (HTTP, empty or unparseable answer). */
  error?: string;
  inputTokens: number;
  cachedInputTokens: number;
  outputTokens: number;
  reasoningTokens: number;
  usd: number;
  ms: number;
};

const TOKENS_SCHEMA = {
  type: "object",
  properties: {
    tokens: {
      type: "array",
      items: {
        type: "object",
        properties: { text: { type: "string" }, reading: { type: "string" } },
        required: ["text", "reading"],
        additionalProperties: false,
      },
    },
  },
  required: ["tokens"],
  additionalProperties: false,
} as const;

function parseRaw(text: unknown): RawToken[] | null {
  if (typeof text !== "string" || !text.trim()) return null;
  try {
    const json = JSON.parse(text.trim().replace(/^```(?:json)?\s*|\s*```$/g, ""));
    const tokens = (json as { tokens?: unknown })?.tokens;
    if (!Array.isArray(tokens)) return null;
    return tokens
      .filter((t): t is { text: string; reading?: unknown } => typeof t?.text === "string")
      .map((t) => ({ text: t.text, ...(typeof t.reading === "string" ? { reading: t.reading } : {}) }));
  } catch {
    return null;
  }
}

/** Retries rate limits, server errors and timeouts (a stuck route, not the model's answer). */
async function withRetries(fn: () => Promise<Response>): Promise<Response> {
  for (let attempt = 1; ; attempt++) {
    try {
      const response = await fn();
      if ((response.status === 429 || response.status >= 500) && attempt < 4) {
        await new Promise((r) => setTimeout(r, 1500 * attempt));
        continue;
      }
      return response;
    } catch (error) {
      if (attempt >= 3) throw error;
    }
  }
}

async function callGemini(spec: ModelSpec, prompt: string): Promise<CallResult> {
  const started = Date.now();
  const thinking =
    spec.model.startsWith("gemini-2.") || spec.effort === "none"
      ? undefined
      : { thinkingLevel: spec.effort === "minimal" && !spec.model.includes("flash-lite") ? "low" : spec.effort };
  const response = await withRetries(() =>
    fetch(`https://generativelanguage.googleapis.com/v1beta/models/${spec.model}:generateContent`, {
      method: "POST",
      headers: { "x-goog-api-key": env("GEMINI_API_KEY"), "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          seed: SEED,
          ...(thinking ? { thinkingConfig: thinking } : {}),
          responseMimeType: "application/json",
          responseSchema: {
            type: "object",
            properties: {
              tokens: {
                type: "array",
                items: {
                  type: "object",
                  properties: { text: { type: "string" }, reading: { type: "string" } },
                  required: ["text", "reading"],
                },
              },
            },
            required: ["tokens"],
          },
        },
      }),
      signal: AbortSignal.timeout(90_000),
    })
  );
  const ms = Date.now() - started;
  const json = await response.json().catch(() => null);
  const u = json?.usageMetadata ?? {};
  const inputTokens = Number(u.promptTokenCount ?? 0);
  const outputTokens = Number(u.candidatesTokenCount ?? 0);
  const reasoningTokens = Number(u.thoughtsTokenCount ?? 0);
  const usd = estimateGeminiCostUSD(spec.model, inputTokens, outputTokens + reasoningTokens) ?? 0;
  const base = { inputTokens, cachedInputTokens: Number(u.cachedContentTokenCount ?? 0), outputTokens, reasoningTokens, usd, ms };
  if (!response.ok) return { ...base, raw: null, error: `HTTP ${response.status}: ${JSON.stringify(json).slice(0, 200)}` };
  const text = json?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p?.text ?? "").join("");
  const raw = parseRaw(text);
  return raw ? { ...base, raw } : { ...base, raw: null, error: `Unparseable answer: ${String(text).slice(0, 200)}` };
}

async function callOpenRouter(spec: ModelSpec, prompt: string): Promise<CallResult> {
  const started = Date.now();
  const response = await withRetries(() =>
    fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env("OPENROUTER_API_KEY")}`,
        "Content-Type": "application/json",
        "X-Title": "Shizen tokenize compare",
      },
      body: JSON.stringify({
        model: spec.model,
        messages: [{ role: "user", content: prompt }],
        seed: SEED,
        reasoning: spec.effort === "none" ? { enabled: false } : { effort: spec.effort, exclude: true },
        response_format: {
          type: "json_schema",
          json_schema: { name: "tokens", strict: true, schema: TOKENS_SCHEMA },
        },
        // Only route to providers that honour the schema, so a miss is the model's, not the router's.
        provider: { require_parameters: true },
        usage: { include: true },
      }),
      signal: AbortSignal.timeout(60_000),
    })
  );
  const ms = Date.now() - started;
  const json = await response.json().catch(() => null);
  const u = json?.usage ?? {};
  const base = {
    inputTokens: Number(u.prompt_tokens ?? 0),
    cachedInputTokens: Number(u.prompt_tokens_details?.cached_tokens ?? 0),
    outputTokens: Number(u.completion_tokens ?? 0) - Number(u.completion_tokens_details?.reasoning_tokens ?? 0),
    reasoningTokens: Number(u.completion_tokens_details?.reasoning_tokens ?? 0),
    usd: Number(u.cost ?? 0),
    ms,
  };
  if (!response.ok || json?.error) {
    return { ...base, raw: null, error: `HTTP ${response.status}: ${JSON.stringify(json?.error ?? json).slice(0, 200)}` };
  }
  const choice = json?.choices?.[0];
  const raw = parseRaw(choice?.message?.content);
  return raw
    ? { ...base, raw }
    : { ...base, raw: null, error: `Unparseable answer (finish: ${choice?.finish_reason}): ${String(choice?.message?.content).slice(0, 200)}` };
}

type LineResult = {
  status: "ok" | "retry" | "failed" | "error";
  tokens: Tok[] | null;
  calls: CallResult[];
};

/** Production's flow: the prompt, then the retry prompt if the tokens don't fit the line. */
async function tokenizeLine(spec: ModelSpec, text: string): Promise<LineResult> {
  const call = spec.provider === "gemini" ? callGemini : callOpenRouter;
  const calls: CallResult[] = [];
  for (const isRetry of [false, true]) {
    let result: CallResult;
    try {
      result = await call(spec, buildTokenizePrompt(text, isRetry));
    } catch (error) {
      result = { raw: null, error: (error as Error).message, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, reasoningTokens: 0, usd: 0, ms: 0 };
    }
    calls.push(result);
    if (result.error && !result.raw && !result.error.startsWith("Unparseable")) {
      return { status: "error", tokens: null, calls };
    }
    const tokens = result.raw ? tokensWithReadings(result.raw, text) : null;
    if (tokens) return { status: isRetry ? "retry" : "ok", tokens, calls };
  }
  return { status: "failed", tokens: null, calls };
}

// ── Scoring ──────────────────────────────────────────────────────────────

/** Token spans in the line (tokens are substrings in order; punctuation is not a token). */
function spans(tokens: Tok[], text: string): Array<{ start: number; end: number; tok: Tok }> {
  const out: Array<{ start: number; end: number; tok: Tok }> = [];
  let from = 0;
  for (const tok of tokens) {
    const start = text.indexOf(tok.text, from);
    if (start < 0) break;
    out.push({ start, end: start + tok.text.length, tok });
    from = start + tok.text.length;
  }
  return out;
}

const hira = (s: string) => s.replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60));

type Score = {
  lines: number;
  exact: number;
  sameSplit: number;
  boundaryHit: number;
  boundaryCand: number;
  boundaryRef: number;
  readingSame: number;
  readingCompared: number;
  digitReadingSame: number;
  digitReadingCompared: number;
};
const emptyScore = (): Score => ({
  lines: 0, exact: 0, sameSplit: 0, boundaryHit: 0, boundaryCand: 0, boundaryRef: 0,
  readingSame: 0, readingCompared: 0, digitReadingSame: 0, digitReadingCompared: 0,
});

function score(into: Score, cand: Tok[], ref: Tok[], text: string) {
  into.lines++;
  if (sameTokens(cand, ref)) into.exact++;
  if (cand.length === ref.length && cand.every((t, i) => t.text === ref[i].text)) into.sameSplit++;
  const c = spans(cand, text);
  const r = spans(ref, text);
  // Token edges inside the line (not the end): where a learner's tap would split.
  const edges = (s: typeof c) => new Set(s.slice(0, -1).map((x) => x.end).concat(s.slice(1).map((x) => x.start)));
  const ce = edges(c);
  const re = edges(r);
  into.boundaryCand += ce.size;
  into.boundaryRef += re.size;
  for (const e of ce) if (re.has(e)) into.boundaryHit++;
  const refBySpan = new Map(r.map((x) => [`${x.start}:${x.end}`, x.tok]));
  for (const x of c) {
    const other = refBySpan.get(`${x.start}:${x.end}`);
    if (!other?.reading) continue;
    const same = hira(x.tok.reading ?? "") === hira(other.reading);
    into.readingCompared++;
    if (same) into.readingSame++;
    if (/[0-9０-９]/.test(x.tok.text)) {
      into.digitReadingCompared++;
      if (same) into.digitReadingSame++;
    }
  }
}

const pct = (n: number, d: number) => (d === 0 ? "  -  " : `${((100 * n) / d).toFixed(1).padStart(5)}%`);
function f1(s: Score) {
  const p = s.boundaryCand ? s.boundaryHit / s.boundaryCand : 0;
  const r = s.boundaryRef ? s.boundaryHit / s.boundaryRef : 0;
  return p + r === 0 ? 0 : (2 * p * r) / (p + r);
}

const show = (tokens: Tok[] | null) =>
  tokens ? tokens.map((t) => (t.reading && t.reading !== t.text ? `${t.text}(${t.reading})` : t.text)).join(" | ") : "—";

// ── Main ─────────────────────────────────────────────────────────────────

async function main() {
  const specs = (option("--models")?.split(",") ?? DEFAULT_MODELS).map((s) => parseModel(s.trim()));
  const count = Number(option("--lines") ?? 150);
  const seed = Number(option("--seed") ?? 1);
  const clipIds = option("--clips")?.split(",").map((s) => s.trim()).filter(Boolean);
  const outDir = option("--out") ?? join(tmpdir(), `clip-tokenize-compare-${new Date().toISOString().replace(/[:.]/g, "-")}`);
  for (const s of specs) env(s.provider === "gemini" ? "GEMINI_API_KEY" : "OPENROUTER_API_KEY");

  const { lines, pool, sentencesPerClip } = await loadLines(clipIds, count, seed);
  const fixed = lines.filter((l) => l.handFixed).length;
  console.log(
    `${lines.length} lines (of ${pool} distinct tokenized lines; seed ${seed}), ${fixed} hand-fixed. Models: ${specs.map((s) => s.label).join(", ")}\n`
  );

  const results = new Map<string, LineResult[]>();
  await Promise.all(
    specs.map(async (spec) => {
      const out: LineResult[] = new Array(lines.length);
      let next = 0;
      let done = 0;
      await Promise.all(
        Array.from({ length: CONCURRENCY }, async () => {
          while (next < lines.length) {
            const i = next++;
            out[i] = await tokenizeLine(spec, lines[i].text);
            if (++done % 25 === 0) console.log(`  ${spec.label}: ${done}/${lines.length}`);
          }
        })
      );
      results.set(spec.label, out);
    })
  );

  // Summary per model.
  const tags = ["digits", "contraction", "n-desu", "long"];
  const rows: string[] = [];
  const summary: Record<string, unknown> = {};
  for (const spec of specs) {
    const res = results.get(spec.label)!;
    const all = emptyScore();
    const hand = emptyScore();
    const byTag = Object.fromEntries(tags.map((t) => [t, emptyScore()]));
    const status = { ok: 0, retry: 0, failed: 0, error: 0 };
    let usd = 0;
    let input = 0;
    let cachedInput = 0;
    let output = 0;
    let reasoning = 0;
    const times: number[] = [];
    res.forEach((r, i) => {
      status[r.status]++;
      for (const c of r.calls) {
        usd += c.usd;
        input += c.inputTokens;
        cachedInput += c.cachedInputTokens;
        output += c.outputTokens;
        reasoning += c.reasoningTokens;
      }
      times.push(r.calls.reduce((n, c) => n + c.ms, 0));
      if (!r.tokens) return;
      const line = lines[i];
      score(all, r.tokens, line.current, line.text);
      if (line.handFixed) score(hand, r.tokens, line.current, line.text);
      for (const t of line.tags) score(byTag[t], r.tokens, line.current, line.text);
    });
    times.sort((a, b) => a - b);
    const perLine = usd / lines.length;
    const n = lines.length;
    rows.push(
      [
        spec.label,
        `ok ${pct(status.ok, n)} retry ${pct(status.retry, n)} failed ${pct(status.failed + status.error, n)}${status.error ? ` (${status.error} errors)` : ""}`,
        `vs current: exact ${pct(all.exact, all.lines)}  same split ${pct(all.sameSplit, all.lines)}  boundary F1 ${(100 * f1(all)).toFixed(1)}  readings ${pct(all.readingSame, all.readingCompared)}  digit readings ${pct(all.digitReadingSame, all.digitReadingCompared)}`,
        `exact by kind: ${tags.map((t) => `${t} ${pct(byTag[t].exact, byTag[t].lines).trim()} (${byTag[t].lines})`).join("  ")}`,
        hand.lines ? `vs hand fixes (${hand.lines}): exact ${pct(hand.exact, hand.lines)}  same split ${pct(hand.sameSplit, hand.lines)}` : "vs hand fixes: none in sample",
        `cost: $${usd.toFixed(4)} total, $${perLine.toFixed(6)}/line, ≈ $${(perLine * sentencesPerClip).toFixed(4)}/clip (${sentencesPerClip.toFixed(1)} lines)` +
          `  tokens/line: ${Math.round(input / n)} in (${Math.round(cachedInput / n)} cached), ${Math.round(output / n)} out, ${Math.round(reasoning / n)} reasoning`,
        `latency: p50 ${(times[Math.floor(n / 2)] / 1000).toFixed(1)}s  p95 ${(times[Math.floor(n * 0.95)] / 1000).toFixed(1)}s`,
      ].join("\n  ")
    );
    summary[spec.label] = { status, all, hand, byTag, usd, perLine, input, cachedInput, output, reasoning, p50ms: times[Math.floor(n / 2)] };
  }
  console.log(`\n${rows.join("\n\n")}\n`);

  // Diff report: every line where some model differs from the current tokens.
  mkdirSync(outDir, { recursive: true });
  const width = Math.max(7, ...specs.map((s) => s.label.length));
  const md: string[] = [
    `# Tokenize compare (${lines.length} lines, seed ${seed})`,
    "",
    "Lines where at least one model differs from the clip's current tokens. `(=)` marks a model that matches. Token(reading); readings equal to the surface are omitted.",
    "",
  ];
  let differing = 0;
  lines.forEach((line, i) => {
    const outs = specs.map((s) => results.get(s.label)![i]);
    if (outs.every((r) => r.tokens && sameTokens(r.tokens, line.current))) return;
    differing++;
    md.push(
      `### ${line.clipId} #${line.index}${line.handFixed ? " · hand-fixed" : ""}${line.tags.length ? ` · ${line.tags.join(", ")}` : ""}`,
      "",
      "```",
      line.text,
      `${"current".padEnd(width)}  ${show(line.current)}`,
      ...specs.map((s, j) => {
        const r = outs[j];
        const mark = r.tokens && sameTokens(r.tokens, line.current) ? "(=)" : r.status === "ok" ? "" : `[${r.status}]`;
        return `${s.label.padEnd(width)}  ${mark === "(=)" ? "(=)" : `${show(r.tokens)} ${mark}`.trim()}`;
      }),
      "```",
      ""
    );
  });
  writeFileSync(join(outDir, "diff.md"), md.join("\n"));
  writeFileSync(
    join(outDir, "results.json"),
    JSON.stringify(
      {
        at: new Date().toISOString(),
        seed,
        models: specs.map((s) => s.label),
        summary,
        lines: lines.map((line, i) => ({
          ...line,
          results: Object.fromEntries(
            specs.map((s) => {
              const r = results.get(s.label)![i];
              return [s.label, { status: r.status, tokens: r.tokens, errors: r.calls.map((c) => c.error).filter(Boolean) }];
            })
          ),
        })),
      },
      null,
      2
    )
  );
  console.log(`${differing} lines differ somewhere. Report: ${join(outDir, "diff.md")}\nRaw results: ${join(outDir, "results.json")}`);
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
