// Makes the next batch of clips from the clip queue, end to end:
//
//   pnpm clip:queue-batch 10              # pick 10, fetch audio, process, report
//   pnpm clip:queue-batch 10 --dry-run    # just show which Shorts it would pick
//   pnpm clip:queue-batch 7 --channel seju   # several from one channel (name or id contains "seju")
//   pnpm clip:queue-batch --resume        # finish clips a stopped run left half-done
//   pnpm clip:queue-batch --report short-abc,short-def
//
// Picks the next Shorts in To do (no warnings), one per channel, preferring
// channels that haven't been tried yet. Saves them as pending clips, fetches
// their audio with public/clip-fetch.mjs (yt-dlp + ffmpeg on this machine),
// then runs every step on a few clips at once: video info, transcribe,
// tokenize, align, translate, level, feed. Each clip only gets the steps it
// is missing, so re-running (or --resume) after a timeout picks up where it
// stopped. Ends with a report: level, feed verdict, timing quality, cost.
//
// Talks to Studio over HTTP. Default: the local dev server
// (http://localhost:3000, which uses the same R2 and database as prod).
// `--studio https://shizen-studio.vercel.app` runs against prod instead; that
// needs STUDIO_AGENT_TOKEN in .env.local (same value as in Vercel).
import { spawn } from "node:child_process";
import path from "node:path";
import { runCost } from "../lib/experiments/clips/usage-cost";
import type { ClipDraft, ClipSummary, ClipUsageRun } from "../lib/experiments/clips/types";
import { clipQueueClipId, type ClipQueueRow } from "../lib/experiments/clips/queue";

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(name);
const option = (name: string) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const STUDIO = (option("--studio") ?? process.env.CLIP_STUDIO_URL ?? "http://localhost:3000").replace(/\/$/, "");
const CONCURRENCY = Number(option("--concurrency") ?? 5);
const STEP_TIMEOUT_MS = 8 * 60_000;
const STEPS = ["video-info", "transcribe", "tokenize", "align", "translate", "level", "feed"] as const;
type Step = (typeof STEPS)[number];

const headers: Record<string, string> = { "Content-Type": "application/json" };
const agentToken = process.env.STUDIO_AGENT_TOKEN?.trim();
if (agentToken) headers.Authorization = `Bearer ${agentToken}`;

async function api<T>(pathname: string, init: RequestInit = {}, timeoutMs = 60_000): Promise<T> {
  const response = await fetch(`${STUDIO}${pathname}`, {
    ...init,
    headers: { ...headers, ...(init.headers as Record<string, string> | undefined) },
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    const message = typeof body?.error === "string" ? body.error : JSON.stringify(body?.error ?? body);
    throw new Error(`${init.method ?? "GET"} ${pathname}: HTTP ${response.status} ${message ?? ""}`.trim());
  }
  return response.json() as Promise<T>;
}

const getDraft = async (id: string) => (await api<{ draft: ClipDraft }>(`/api/experiments/clips/${id}`)).draft;

// --- Picking -----------------------------------------------------------

/** Longer audio is cut into several clips, which splits a story Short in two. */
const SPLITS_AT_SECONDS = 120;

function pickFromChannel(rows: ClipQueueRow[], count: number, match: string): ClipQueueRow[] {
  const needle = match.toLowerCase();
  // You asked for this channel, so warnings (a title that says ASMR, a long
  // Short) don't hold a Short back; only one that would be cut in two does.
  return rows
    .filter(
      (r) =>
        r.progress === "none" &&
        r.status === "queued" &&
        (r.channelName.toLowerCase().includes(needle) || (r.channelId ?? "").toLowerCase() === needle) &&
        (r.durationSec ?? 0) <= SPLITS_AT_SECONDS
    )
    .slice(0, count);
}

function pick(rows: ClipQueueRow[], count: number): ClipQueueRow[] {
  const channel = (r: ClipQueueRow) => r.channelId ?? r.channelName;
  // A channel counts as tried once any of its Shorts was clipped or skipped.
  const tried = new Set(rows.filter((r) => r.progress !== "none" || r.status === "skipped").map(channel));
  const todo = rows.filter((r) => r.progress === "none" && r.status === "queued" && r.flags.length === 0);
  const picked: ClipQueueRow[] = [];
  const used = new Set<string>();
  // Untried channels first, then channels already tried; never two from one channel in a batch.
  for (const pass of [(r: ClipQueueRow) => !tried.has(channel(r)), () => true]) {
    for (const r of todo) {
      if (picked.length >= count) break;
      if (used.has(channel(r)) || !pass(r)) continue;
      used.add(channel(r));
      picked.push(r);
    }
  }
  return picked;
}

// --- Fetching audio ----------------------------------------------------

async function fetchAudio(links: string[]): Promise<void> {
  // pnpm runs scripts from webapp/.
  const script = path.resolve("public", "clip-fetch.mjs");
  await new Promise<void>((resolve) => {
    const child = spawn(process.execPath, [script, ...links], { stdio: ["ignore", "pipe", "pipe"] });
    const forward = (chunk: Buffer) => {
      for (const line of chunk.toString().split(/\r?\n|\r/)) {
        // yt-dlp's progress lines are noise here; keep what the script says.
        if (/^(Clip |Created |Done:|\[\d+\/\d+\])/.test(line) || /fail|error|isn’t|limit|no longer/i.test(line)) {
          console.log(`  ${line.trim()}`);
        }
      }
    };
    child.stdout.on("data", forward);
    child.stderr.on("data", forward);
    // A failed Short doesn't stop the batch; the report shows which made it.
    child.on("close", () => resolve());
  });
}

// --- Processing --------------------------------------------------------

function missingSteps(d: ClipDraft): Step[] {
  const s = d.sentences;
  const tokenized = s.length > 0 && s.every((x) => x.tokens && x.tokens.length > 0);
  const aligned = tokenized && s.every((x) => (x.tokens ?? []).every((t) => t.startSec !== undefined));
  const done: Record<Step, boolean> = {
    "video-info": Boolean(d.video),
    transcribe: s.length > 0 || Boolean(d.asr),
    tokenize: tokenized,
    align: aligned,
    translate: s.length > 0 && s.every((x) => Boolean(x.en?.trim())),
    level: Boolean(d.difficulty),
    feed: Boolean(d.feed?.auto || d.feed?.manual),
  };
  return STEPS.filter((step) => !done[step]);
}

async function processClip(id: string): Promise<string[]> {
  const problems: string[] = [];
  // Two rounds: a step that timed out on our side usually finished on the
  // server, so look again before calling it a failure.
  for (let round = 0; round < 2; round++) {
    let draft = await getDraft(id);
    const steps = missingSteps(draft);
    if (steps.length === 0) return [];
    if (draft.asr && draft.sentences.length === 0) return ["no speech"];
    problems.length = 0;
    for (const step of steps) {
      try {
        const body = step === "align" && draft.sentences.some((s) => s.tokens?.some((t) => t.startSec !== undefined))
          ? { onlyUntimed: true }
          : {};
        draft = (
          await api<{ draft: ClipDraft }>(
            `/api/experiments/clips/${id}/${step}`,
            { method: "POST", body: JSON.stringify(body) },
            STEP_TIMEOUT_MS
          )
        ).draft;
        if (step === "transcribe" && draft.sentences.length === 0) return ["no speech"];
      } catch (error) {
        problems.push(`${step}: ${error instanceof Error ? error.message : String(error)}`);
        // Later steps need tokens and timings; the next round retries from here.
        if (step === "transcribe" || step === "tokenize" || step === "align") break;
      }
    }
    if (problems.length === 0) return [];
  }
  return problems;
}

async function processAll(ids: string[]): Promise<Map<string, string[]>> {
  const results = new Map<string, string[]>();
  let cursor = 0;
  let finished = 0;
  const worker = async () => {
    while (cursor < ids.length) {
      const id = ids[cursor++]!;
      const started = Date.now();
      const problems = await processClip(id).catch((e) => [String(e?.message ?? e)]);
      results.set(id, problems);
      finished++;
      console.log(
        `  [${finished}/${ids.length}] ${id} ${problems.length ? "⚠ " + problems.join("; ") : "done"} (${Math.round((Date.now() - started) / 1000)} s)`
      );
    }
  };
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, ids.length) }, worker));
  return results;
}

// --- Report ------------------------------------------------------------

async function report(ids: string[]): Promise<void> {
  let total = 0;
  let inFeed = 0;
  console.log("");
  for (const id of ids) {
    let d: ClipDraft;
    try {
      d = await getDraft(id);
    } catch {
      console.log(`✗ ${id}: not created (see the fetch output above)`);
      continue;
    }
    const cost = (d.usage ?? []).reduce((n: number, u: ClipUsageRun) => n + (runCost(u)?.usd ?? 0), 0);
    total += cost;
    const scores = d.sentences.map((s) => s.score ?? 0);
    const weak = scores.filter((v) => v < 0.3).length;
    const basic = d.sentences.filter((s) => s.basicSplit).length;
    const verdict = d.feed?.manual ? { eligible: d.feed.manual.eligible, reason: "set by hand" } : d.feed?.auto;
    if (verdict?.eligible) inFeed++;
    console.log(
      `${verdict?.eligible ? "✅" : "❌"} ${id}  ${d.video?.channelName ?? "?"} · ${Math.round(d.durationSec)} s · N${d.difficulty?.jlptLevel ?? "?"} · $${cost.toFixed(3)}`
    );
    console.log(`     ${verdict?.reason ?? "no feed verdict"}`);
    const notes = [
      `${d.sentences.length} lines`,
      weak ? `⚠ weak timing ${weak}/${scores.length}` : "timing ok",
      ...(basic ? [`⚠ ${basic} basic-split line(s)`] : []),
    ];
    console.log(`     ${notes.join(" · ")}  ${STUDIO}/experiments/clips/${id}`);
  }
  console.log(`\n${inFeed} of ${ids.length} in the feed · $${total.toFixed(3)} total`);
}

// --- Main --------------------------------------------------------------

async function main() {
  console.log(`Studio: ${STUDIO}${agentToken ? " (agent token)" : ""}`);

  const reportIds = option("--report");
  if (reportIds) return report(reportIds.split(",").map((s) => s.trim()).filter(Boolean));

  if (flag("--resume")) {
    const { clips } = await api<{ clips: ClipSummary[] }>("/api/experiments/clips");
    const unfinished = clips
      .filter((c) => !c.deprecated && (!c.aligned || !c.translated || c.jlptLevel === null || c.videoTitle === null || c.feed === "unchecked"))
      .map((c) => c.id);
    console.log(`${unfinished.length} unfinished clip(s): ${unfinished.join(", ") || "none"}`);
    if (unfinished.length === 0) return;
    await processAll(unfinished);
    return report(unfinished);
  }

  const count = Number(args.find((a) => /^\d+$/.test(a)) ?? 5);
  const { rows } = await api<{ rows: ClipQueueRow[] }>("/api/experiments/clip-queue");
  const channelMatch = option("--channel");
  const picked = channelMatch ? pickFromChannel(rows, count, channelMatch) : pick(rows, count);
  if (picked.length === 0) return console.log("Nothing left in To do.");
  console.log(`\nPicked ${picked.length}:`);
  for (const r of picked) console.log(`  ${r.videoId}  ${r.channelName} · ${r.durationSec ?? "?"} s · ${r.title.slice(0, 50)}`);
  if (flag("--dry-run")) return;

  console.log("\nSaving pending clips…");
  const tickets: { id: string; token: string }[] = [];
  for (const r of picked) {
    try {
      const { pending, token } = await api<{ pending: { id: string }; token: string }>("/api/experiments/clip-uploads", {
        method: "POST",
        body: JSON.stringify({
          id: clipQueueClipId(r.videoId),
          videoId: r.videoId,
          startSec: 0,
          endSec: null,
          orientation: "portrait",
          splitTargetSec: null,
        }),
      });
      tickets.push({ id: pending.id, token });
    } catch (error) {
      console.log(`  skipped ${r.videoId}: ${error instanceof Error ? error.message : error}`);
    }
  }

  console.log(`\nFetching audio for ${tickets.length}…`);
  await fetchAudio(tickets.map((t) => `${STUDIO}/hooks/clip-upload/${t.id}#${t.token}`));

  // A long Short is split into <id>-01, <id>-02…; process whatever was made.
  const { clips } = await api<{ clips: ClipSummary[] }>("/api/experiments/clips");
  const made = clips
    .map((c) => c.id)
    .filter((id) => tickets.some((t) => id === t.id || id.startsWith(`${t.id}-`)))
    .sort();
  // The pending records only existed to hand over the audio.
  await Promise.all(tickets.map((t) => api(`/api/experiments/clip-uploads/${t.id}`, { method: "DELETE" }).catch(() => undefined)));
  // A Short whose audio couldn't be fetched (deleted, private, region-locked)
  // is skipped in the queue, so the next batch doesn't pick it again.
  const failed = picked.filter((r) => !made.some((id) => id === clipQueueClipId(r.videoId) || id.startsWith(`${clipQueueClipId(r.videoId)}-`)));
  if (failed.length > 0) {
    await api("/api/experiments/clip-queue", {
      method: "PATCH",
      body: JSON.stringify({ videoIds: failed.map((r) => r.videoId), status: "skipped", note: "Couldn’t fetch the audio (batch script)." }),
    }).catch(() => undefined);
    console.log(`Skipped in the queue (no audio): ${failed.map((r) => r.videoId).join(", ")}`);
  }

  console.log(`\nProcessing ${made.length} clip(s), ${CONCURRENCY} at a time…`);
  await processAll(made);
  await report(made);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
