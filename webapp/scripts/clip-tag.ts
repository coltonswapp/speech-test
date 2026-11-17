// Catalog tags for clips (format, topics, register, speakers, dialect, series;
// see lib/experiments/clips/tags.ts).
//
//   pnpm clip:tag                      # dry run: ask Gemini here, save nothing, report
//   pnpm clip:tag --write              # run the Tag step (via Studio) on untagged clips
//   pnpm clip:tag --write --retag      # …on every clip (after growing the vocabulary)
//   pnpm clip:tag --ids a,b --limit 20 --out tags.json --all
//
// Only aligned, non-deprecated clips unless --all. --write goes through
// Studio (CLIP_STUDIO_URL or --studio, default http://localhost:3000), so the
// draft, its cost log and the clip index are updated exactly as the Tag
// button does. The report ends with the vocabulary suggestions the model
// made: values worth adding to tags.ts when they keep coming up.
import { writeFileSync } from "node:fs";
import { GetObjectCommand, ListObjectsV2Command, S3Client } from "@aws-sdk/client-s3";
import { clipDraftSchema, type ClipDraft } from "../lib/experiments/clips/types";
import {
  buildClipTagPrompt,
  CLIP_TAGS_GEMINI_SCHEMA,
  clipEffectiveTags,
  clipTagInput,
  parseClipTagAnswer,
  type ClipTagValues,
} from "../lib/experiments/clips/tags";

const ROOT = "experiments/clips/";
const CONCURRENCY = 4;

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(name);
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

const STUDIO = (option("--studio") ?? process.env.CLIP_STUDIO_URL ?? "http://localhost:3000").replace(/\/$/, "");
const studioHeaders: Record<string, string> = { "Content-Type": "application/json" };
const agentToken = process.env.STUDIO_AGENT_TOKEN?.trim();
if (agentToken) studioHeaders.Authorization = `Bearer ${agentToken}`;

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

type Result = {
  id: string;
  title?: string;
  tags?: ClipTagValues;
  reason?: string;
  suggested: string[];
  error?: string;
  inputTokens: number;
  outputTokens: number;
};

/** Dry run: the Tag step's prompt and checks, called from here. */
async function tagHere(draft: ClipDraft, model: string, apiKey: string): Promise<Result> {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: buildClipTagPrompt(clipTagInput(draft)) }] }],
        generationConfig: {
          ...(model.startsWith("gemini-2.") ? {} : { thinkingConfig: { thinkingLevel: "low" } }),
          responseMimeType: "application/json",
          responseSchema: CLIP_TAGS_GEMINI_SCHEMA,
        },
      }),
      signal: AbortSignal.timeout(120_000),
    }
  );
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${(await response.text()).slice(0, 300)}`);
  const json = await response.json();
  const raw = json?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p?.text ?? "").join("");
  const answer = parseClipTagAnswer(JSON.parse(raw));
  if (!answer) throw new Error("Answer didn't fit the vocabulary.");
  const usage = json?.usageMetadata ?? {};
  return {
    id: draft.id,
    title: draft.video?.title,
    tags: answer.pick,
    reason: answer.reason,
    suggested: answer.suggested,
    inputTokens: usage.promptTokenCount ?? 0,
    outputTokens: (usage.candidatesTokenCount ?? 0) + (usage.thoughtsTokenCount ?? 0),
  };
}

/** --write: the Tag step through Studio. */
async function tagViaStudio(draft: ClipDraft): Promise<Result> {
  const response = await fetch(`${STUDIO}/api/experiments/clips/${draft.id}/tag`, {
    method: "POST",
    headers: studioHeaders,
    signal: AbortSignal.timeout(5 * 60_000),
  });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${body?.error ?? ""}`);
  const next = body.draft as ClipDraft;
  const run = next.usage?.at(-1);
  return {
    id: draft.id,
    title: draft.video?.title,
    // A hand-set answer still wins; report what the clip now carries.
    tags: clipEffectiveTags(next.tags) ?? undefined,
    reason: next.tags?.auto?.reason,
    suggested: next.tags?.auto?.suggested ?? [],
    inputTokens: run?.step === "tag" ? run.inputTokens : 0,
    outputTokens: run?.step === "tag" ? run.outputTokens + run.thinkingTokens : 0,
  };
}

function tally(values: string[]): string {
  const counts = new Map<string, number>();
  for (const v of values) counts.set(v, (counts.get(v) ?? 0) + 1);
  return [...counts].sort((a, b) => b[1] - a[1]).map(([k, n]) => `${k} ${n}`).join(" · ") || "-";
}

async function main() {
  const write = flag("--write");
  const retag = flag("--retag");
  const limit = Number(option("--limit") ?? Infinity);
  const only = option("--ids")?.split(",").map((s) => s.trim()).filter(Boolean);
  const out = option("--out");
  const model = option("--model") ?? process.env.GEMINI_TAG_MODEL?.trim() ?? "gemini-3.8-flash";
  const apiKey = write ? "" : env("GEMINI_API_KEY");

  const ids = only ?? (await listDraftIds());
  const drafts: ClipDraft[] = [];
  for (let i = 0; i < ids.length; i += 20) {
    const batch = await Promise.all(ids.slice(i, i + 20).map(readDraft));
    drafts.push(...batch.filter((d): d is ClipDraft => d !== null));
  }
  const picked = drafts
    .filter((d) => d.sentences.length > 0)
    .filter((d) => flag("--all") || only || (!d.deprecated && d.alignment))
    .filter((d) => !write || retag || only || !(d.tags?.auto || d.tags?.manual))
    .slice(0, limit);
  console.log(
    `${drafts.length} drafts; ${write ? `tagging ${picked.length} through ${STUDIO}` : `dry run on ${picked.length} with ${model} (nothing saved)`}…`
  );

  const results: Result[] = [];
  let next = 0;
  await Promise.all(
    Array.from({ length: CONCURRENCY }, async () => {
      while (next < picked.length) {
        const draft = picked[next++];
        let result: Result | undefined;
        for (let attempt = 1; attempt <= 2 && !result?.tags; attempt++) {
          try {
            result = write ? await tagViaStudio(draft) : await tagHere(draft, model, apiKey);
          } catch (error) {
            result = { id: draft.id, suggested: [], error: (error as Error).message, inputTokens: 0, outputTokens: 0 };
          }
        }
        results.push(result!);
        const t = result!.tags;
        console.log(
          t
            ? `  ${result!.id}: ${t.format} | ${t.topics.join(",") || "-"} | ${t.register}/${t.speakers}/${t.dialect}${t.series ? ` | ${t.series}` : ""}${result!.suggested.length ? `  (suggests ${result!.suggested.join(", ")})` : ""}`
            : `  ✗ ${result!.id}: ${result!.error}`
        );
      }
    })
  );
  results.sort((a, b) => a.id.localeCompare(b.id));
  if (out) writeFileSync(out, JSON.stringify({ model, write, at: new Date().toISOString(), results }, null, 2));

  const ok = results.flatMap((r) => (r.tags ? [r.tags] : []));
  const sum = (k: "inputTokens" | "outputTokens") => results.reduce((s, r) => s + r[k], 0);
  console.log(
    `\nTagged ${ok.length}/${results.length}. Tokens: ${sum("inputTokens")} in, ${sum("outputTokens")} out (incl. thinking).`
  );
  if (ok.length > 0) {
    console.log(`format:    ${tally(ok.map((t) => t.format))}`);
    console.log(`topics:    ${tally(ok.flatMap((t) => (t.topics.length ? t.topics : ["(none)"])))}`);
    console.log(`register:  ${tally(ok.map((t) => t.register))}`);
    console.log(`speakers:  ${tally(ok.map((t) => t.speakers))}`);
    console.log(`dialect:   ${tally(ok.map((t) => t.dialect))}`);
    console.log(`series:    ${tally(ok.flatMap((t) => (t.series ? [t.series] : [])))}`);
  }
  const suggestions = results.flatMap((r) => r.suggested);
  console.log(
    `\nVocabulary suggestions (add to lib/experiments/clips/tags.ts if they keep coming up): ${tally(suggestions)}`
  );
  if (out) console.log(`Wrote ${out}`);
  process.exit(results.some((r) => r.error) ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
