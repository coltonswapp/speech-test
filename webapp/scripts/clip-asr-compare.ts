// Clip transcription comparison: runs several speech-to-text models on one
// clip's stored audio and prints where they disagree with the saved
// transcript and with each other. No answer key needed: lines every model
// agrees on are probably right; the disagreements are what to listen to.
//
//   pnpm clip:asr-compare <clip-id> [<clip-id>…] [--models a,b,c]
//   pnpm clip:asr-compare --find うま [--prefix riko-film-osaka]
//
// Model names starting with "gemini-" go to Gemini with the Studio ASR prompt;
// anything else goes to OpenAI's transcription endpoint.
import { GetObjectCommand, ListObjectsV2Command, S3Client } from "@aws-sdk/client-s3";
import { ASR_PROMPT, splitLongAsrLines } from "../lib/experiments/clips/asr-lines";

const ROOT = "experiments/clips/";

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

async function getObject(key: string): Promise<Buffer> {
  const out = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  return Buffer.from(await out.Body!.transformToByteArray());
}

async function listClipIds(prefix: string): Promise<string[]> {
  const ids: string[] = [];
  let token: string | undefined;
  do {
    const out = await s3.send(
      new ListObjectsV2Command({ Bucket: bucket, Prefix: ROOT + prefix, Delimiter: "/", ContinuationToken: token })
    );
    for (const p of out.CommonPrefixes ?? []) if (p.Prefix) ids.push(p.Prefix.slice(ROOT.length, -1));
    token = out.NextContinuationToken;
  } while (token);
  return ids;
}

type Draft = { id: string; durationSec: number; sentences: { text: string }[]; asr?: { model: string } };
const readDraft = async (id: string) => JSON.parse((await getObject(`${ROOT}${id}/draft.json`)).toString("utf8")) as Draft;

async function gemini(model: string, wav: Buffer): Promise<string[]> {
  // Dedicated transcription models have no JSON mode: ask for one sentence per line.
  const plain = model.includes("transcribe");
  const prompt = plain
    ? ASR_PROMPT.replace("one per array item", "one per line").replace("return an empty array", "return nothing")
    : ASR_PROMPT;
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "x-goog-api-key": env("GEMINI_API_KEY"), "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          { role: "user", parts: [{ inlineData: { mimeType: "audio/wav", data: wav.toString("base64") } }, { text: prompt }] },
        ],
        ...(plain
          ? {}
          : {
              generationConfig: {
                responseMimeType: "application/json",
                responseSchema: { type: "object", properties: { sentences: { type: "array", items: { type: "string" } } }, required: ["sentences"] },
              },
            }),
      }),
      signal: AbortSignal.timeout(180_000),
    }
  );
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${(await response.text()).slice(0, 300)}`);
  const json = await response.json();
  const raw = json?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p?.text ?? "").join("") ?? "";
  const lines = plain
    ? raw.split("\n").map((s: string) => s.trim()).filter(Boolean)
    : (JSON.parse(raw).sentences as string[]).map((s) => s.trim()).filter(Boolean);
  return splitLongAsrLines(lines);
}

async function openai(model: string, wav: Buffer): Promise<string[]> {
  const form = new FormData();
  form.set("model", model);
  form.set("language", "ja");
  form.set("file", new Blob([new Uint8Array(wav)], { type: "audio/wav" }), "clip.wav");
  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${env("OPENAI_API_KEY")}` },
    body: form,
    signal: AbortSignal.timeout(180_000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${(await response.text()).slice(0, 300)}`);
  const text = String((await response.json()).text ?? "");
  return text.split(/(?<=[。？！?!])/).map((s) => s.trim()).filter(Boolean);
}

/** Kana and kanji only: punctuation, spaces and line breaks aren't disagreements. */
const bare = (lines: string[]) => lines.join("").replace(/[^\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}ー0-9０-９]/gu, "");

/** Differing stretches between two strings (character LCS), with a little context. */
function diffs(a: string, b: string): string[] {
  const n = a.length, m = b.length;
  const dp = Array.from({ length: n + 1 }, () => new Uint16Array(m + 1));
  for (let i = n - 1; i >= 0; i--)
    for (let j = m - 1; j >= 0; j--)
      dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
  const out: string[] = [];
  let i = 0, j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && a[i] === b[j]) { i++; j++; continue; }
    const i0 = i, j0 = j;
    while ((i < n || j < m) && !(i < n && j < m && a[i] === b[j])) {
      if (j >= m || (i < n && dp[i + 1][j] >= dp[i][j + 1])) i++;
      else j++;
    }
    const before = a.slice(Math.max(0, i0 - 6), i0);
    const after = a.slice(i, i + 6);
    out.push(`…${before}[${a.slice(i0, i) || "∅"} → ${b.slice(j0, j) || "∅"}]${after}…`);
  }
  return out;
}

async function main() {
  const args = process.argv.slice(2);
  const flag = (name: string) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
  const find = flag("--find");
  if (find) {
    for (const id of await listClipIds(flag("--prefix") ?? "")) {
      const draft = await readDraft(id).catch(() => null);
      draft?.sentences.forEach((s, i) => { if (s.text.includes(find)) console.log(`${id} line ${i + 1}: ${s.text}`); });
    }
    return;
  }
  const modelsArg = flag("--models");
  const ids = args.filter((a) => !a.startsWith("--") && a !== modelsArg);
  if (ids.length === 0) throw new Error("Usage: clip:asr-compare <clip-id>… [--models a,b] | --find <text> [--prefix p]");
  const models = (modelsArg ?? "gemini-3.8-flash").split(",").map((m) => m.trim()).filter(Boolean);
  /** Per model: characters that differ from each other model, summed over clips. */
  const apart = new Map(models.map((m) => [m, 0]));
  let totalChars = 0;
  for (const id of ids) {
    const [draft, wav] = await Promise.all([readDraft(id), getObject(`${ROOT}${id}/clip.wav`)]);
    console.log(`\n━━ ${id} · ${draft.durationSec.toFixed(1)} s · saved transcript by ${draft.asr?.model ?? "hand"}`);
    const results = await Promise.all(
      models.map(async (model) => {
        const started = Date.now();
        try {
          const lines = await (model.startsWith("gemini-") ? gemini(model, wav) : openai(model, wav));
          return { model, lines, seconds: (Date.now() - started) / 1000, error: null as string | null };
        } catch (error) {
          return { model, lines: [] as string[], seconds: 0, error: error instanceof Error ? error.message : String(error) };
        }
      })
    );
    const ok = results.filter((r) => !r.error);
    for (const r of results) {
      console.log(`\n── ${r.model}${r.error ? ` FAILED: ${r.error}` : ` (${r.seconds.toFixed(1)} s)`}`);
      if (!r.error) console.log(r.lines.map((s) => `  ${s}`).join("\n"));
    }
    // Where the models part ways, against the first one that answered.
    const [base, ...others] = ok;
    if (base) {
      totalChars += bare(base.lines).length;
      for (const other of others) {
        const d = diffs(bare(base.lines), bare(other.lines));
        console.log(`\n   ${base.model} → ${other.model}: ${d.length} differences`);
        for (const x of d) console.log(`     ${x}`);
      }
      for (const a of ok)
        for (const b of ok)
          if (a !== b) apart.set(a.model, (apart.get(a.model) ?? 0) + diffs(bare(a.lines), bare(b.lines)).length);
    }
  }
  console.log(`\n━━ Differing stretches against all other models, over ${ids.length} clips (${totalChars} characters). Lower = agrees with the pack more.`);
  for (const [model, n] of [...apart].sort((x, y) => x[1] - y[1])) console.log(`   ${String(n).padStart(4)}  ${model}`);
}

main().catch((error) => { console.error(error instanceof Error ? error.message : error); process.exit(1); });
