// Karaoke auto-stamp eval (KA-6). Aligns every published take that carries a
// human (or reviewed) tokenSync against the live aligner, post-processes with
// lib/dialogue/token-sync-auto, and reports:
//   1. onset metrics (primary): stamp − RMS onset on clean post-pause tokens
//   2. derived line marks: inside the silence gap, distance to human marks
//   3. human-gold agreement per token class (secondary; editors drift)
//
//   pnpm eval:token-sync [--scenes first-hello,around-the-block/coin-laundry]
//                        [--shift 150] [--json out.json] [--cache .eval-cache]
//                        [--no-readings]
//
// Exit 1 when the v1 onset bar (scene-to-scene sd ≤ 25 ms, within-scene sd
// ≤ 110 ms), the marks bar (100% inside a gap) or monotonicity fails.
// --shift 150 reproduces the prototype's human-gold table on first-hello.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { and, inArray, isNotNull } from "drizzle-orm";
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { db } from "../lib/db/standalone-client";
import { appSettings, dialogueScenario, ttsVariant } from "../lib/db/schema";
import { wavToPcm16, pcm16ToFloat32 } from "../lib/tts/wav";
import { parsePublishedTokenSync } from "../lib/dialogue/token-sync";
import {
  AUTO_STAMP_SHIFT_SECONDS,
  POST_PAUSE_MIN_QUIET_SECONDS,
  autoStampTokenSync,
  buildTrack,
  frameOf,
  isLoud,
  lineGap,
  quietBefore,
  speechOnsetNear,
  type AlignedLine,
} from "../lib/dialogue/token-sync-auto";
import { tokenizeCacheKey } from "../lib/dialogue/token-readings";
import type { PublishedTokenSync } from "../lib/dialogue/types";

type Args = { scenes: string[]; shiftSeconds: number; json: string | null; cache: string; readings: boolean };
function parseArgs(argv: string[]): Args {
  const args: Args = { scenes: [], shiftSeconds: AUTO_STAMP_SHIFT_SECONDS, json: null, cache: ".eval-cache", readings: true };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--scenes") args.scenes = argv[++i].split(",").map((s) => s.trim()).filter(Boolean);
    else if (a === "--shift") args.shiftSeconds = Number(argv[++i]) / 1000;
    else if (a === "--json") args.json = argv[++i];
    else if (a === "--cache") args.cache = argv[++i];
    else if (a === "--no-readings") args.readings = false;
    else throw new Error(`unknown arg ${a}`);
  }
  return args;
}

const PARTICLES = new Set([..."はがをにでとのもへやかねよ", "よね", "ので", "から", "まで", "んですか", "んですね", "んです", "です", "だ", "な"]);

function median(v: number[]): number {
  if (v.length === 0) return NaN;
  const s = [...v].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
function mean(v: number[]): number { return v.length ? v.reduce((a, b) => a + b, 0) / v.length : NaN; }
function sd(v: number[]): number {
  if (v.length < 2) return NaN;
  const m = mean(v);
  return Math.sqrt(v.reduce((a, b) => a + (b - m) ** 2, 0) / (v.length - 1));
}
function pct(v: number[], lim: number): number { return v.length ? (100 * v.filter((x) => x <= lim).length) / v.length : NaN; }
function p95(v: number[]): number { const s = [...v].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(0.95 * s.length))]; }
const f0 = (x: number) => (Number.isFinite(x) ? x.toFixed(0) : "-");
const f1 = (x: number) => (Number.isFinite(x) ? x.toFixed(1) : "-");

type Row = { scene: string; line: number; tok: number; text: string; deltaMs: number; first: boolean; particle: boolean; singleChar: boolean; postPause: boolean };
function classLine(label: string, rows: Row[]): string {
  const a = rows.map((r) => Math.abs(r.deltaMs));
  const s = rows.map((r) => r.deltaMs);
  if (!a.length) return `${label.padStart(14)}: n=0`;
  return `${label.padStart(14)}: n=${String(a.length).padStart(4)} med|Δ|=${f0(median(a)).padStart(4)} p95|Δ|=${f0(p95(a)).padStart(4)} ≤50:${f1(pct(a, 50)).padStart(5)}% ≤100:${f1(pct(a, 100)).padStart(5)}% ≤150:${f1(pct(a, 150)).padStart(5)}% bias=${(median(s) >= 0 ? "+" : "") + f0(median(s))}`;
}

async function alignerCall(url: string, token: string, body: unknown, cacheFile: string | null) {
  if (cacheFile && existsSync(cacheFile)) return JSON.parse(readFileSync(cacheFile, "utf8"));
  const res = await fetch(`${url.replace(/\/+$/, "")}/align`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`aligner ${res.status}: ${await res.text()}`);
  const json = await res.json();
  if (cacheFile) writeFileSync(cacheFile, JSON.stringify(json));
  return json;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const alignerUrl = process.env.ALIGNER_URL;
  const alignerToken = process.env.ALIGNER_TOKEN;
  if (!alignerUrl || !alignerToken) throw new Error("ALIGNER_URL / ALIGNER_TOKEN not set");
  const s3 = new S3Client({
    region: "auto",
    endpoint: process.env.R2_ENDPOINT!,
    credentials: { accessKeyId: process.env.R2_ACCESS_KEY_ID!, secretAccessKey: process.env.R2_SECRET_ACCESS_KEY! },
  });
  const bucket = process.env.R2_BUCKET_NAME!;
  mkdirSync(args.cache, { recursive: true });

  // Gold: published scenes whose tokenSync is human-made (absent source = legacy human).
  const scenes = (
    await db.select().from(dialogueScenario).where(and(isNotNull(dialogueScenario.tokenSync), isNotNull(dialogueScenario.publishedVariantId)))
  )
    .filter((s) => {
      const src = (s.tokenSync as { source?: string } | null)?.source;
      return src == null || src === "human" || src === "reviewed";
    })
    .filter((s) => args.scenes.length === 0 || args.scenes.some((f) => s.id === f || s.id.startsWith(`${f}/`)))
    .sort((a, b) => a.id.localeCompare(b.id));
  if (scenes.length === 0) throw new Error("no gold scenes matched");
  const variants = await db.select().from(ttsVariant).where(inArray(ttsVariant.id, scenes.map((s) => s.publishedVariantId!)));
  const byId = new Map(variants.map((v) => [v.id, v]));

  const rows: Row[] = [];
  const onsetOffsets: number[] = [];
  const perSceneOnset: Record<string, number[]> = {};
  const markResults: Array<{ scene: string; inGap: boolean; deltaHumanMs: number | null }> = [];
  let monotonicViolations = 0;
  const flagCounts: Record<string, number> = {};
  const perScene: Array<Record<string, unknown>> = [];
  let readingsUsed = 0, tokensTotal = 0;

  for (const scene of scenes) {
    const gold = parsePublishedTokenSync(scene.tokenSync) as PublishedTokenSync | null;
    const variant = byId.get(scene.publishedVariantId!);
    if (!gold || !variant) { console.warn(`skip ${scene.id}: missing gold/variant`); continue; }
    const t0 = performance.now();

    // Readings from the tokenize cache only (never calls Gemini here).
    const readingByLine = new Map<string, Map<string, string>>();
    if (args.readings) {
      const keys = gold.lines.map((l) => tokenizeCacheKey(l.text));
      const cached = await db.select().from(appSettings).where(inArray(appSettings.key, keys));
      const byKey = new Map(cached.map((c) => [c.key, c.value as { tokens: Array<{ text: string; reading?: string }> }]));
      gold.lines.forEach((l, i) => {
        const entry = byKey.get(keys[i]);
        if (entry) readingByLine.set(l.text, new Map(entry.tokens.filter((t) => t.reading).map((t) => [t.text, t.reading!])));
      });
    }
    const lines = gold.lines.map((l) => ({
      text: l.text,
      tokens: l.tokens.map((t) => {
        const reading = readingByLine.get(l.text)?.get(t.text);
        tokensTotal++; if (reading) readingsUsed++;
        return { text: t.text, ...(reading ? { reading } : {}) };
      }),
    }));

    const wavBytes = Buffer.from(await (await s3.send(new GetObjectCommand({ Bucket: bucket, Key: variant.audioObjectKey }))).Body!.transformToByteArray());
    const { pcm, sampleRate } = wavToPcm16(wavBytes);
    const samples = pcm16ToFloat32(pcm);
    const audioUrl = await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: variant.audioObjectKey }), { expiresIn: 600 });
    const cacheFile = path.join(args.cache, `${scene.id.replace(/\//g, "__")}.${args.readings ? "r" : "nr"}.json`);
    const aligned = await alignerCall(alignerUrl, alignerToken, { audioUrl, lines }, cacheFile);
    const alignedLines = aligned.lines as AlignedLine[];

    const result = autoStampTokenSync({
      alignerVersion: aligned.alignerVersion, aligned: alignedLines, lines, samples, sampleRate,
      contentHash: gold.contentHash, existingMarkSamples: null, options: { shiftSeconds: args.shiftSeconds },
    });
    for (const f of result.flags) flagCounts[f.code] = (flagCounts[f.code] ?? 0) + 1;
    const trim = (variant.trimSampleLower ?? 0) / sampleRate;
    const track = buildTrack(samples, sampleRate);

    // 1. onset offsets on clean post-pause, non-first tokens (raw aligner onset).
    const sceneOffsets: number[] = [];
    let prev = -Infinity;
    result.tokenSync.lines.forEach((pl, li) => pl.tokens.forEach((pt, ti) => {
      if (pt.startSeconds == null) return;
      if (pt.startSeconds <= prev) monotonicViolations++;
      prev = pt.startSeconds;
      if (ti === 0) return;
      const raw = alignedLines[li].tokens[ti].startSeconds;
      const onset = speechOnsetNear(track, raw);
      if (!isLoud(track, frameOf(track, onset))) return;
      if (quietBefore(track, onset) < POST_PAUSE_MIN_QUIET_SECONDS) return;
      sceneOffsets.push((pt.startSeconds - onset) * 1000);
    }));
    onsetOffsets.push(...sceneOffsets);
    perSceneOnset[scene.id] = sceneOffsets;

    // 2. derived marks: inside silence, after previous speech, before next onset.
    const humanMarks = (variant.dialogueLineSwitchSamples ?? []).map((s) => s / sampleRate).sort((a, b) => a - b);
    result.markSamples.forEach((ms, i) => {
      const m = ms / sampleRate;
      const gap = lineGap(track, alignedLines, i + 1);
      const inGap =
        !isLoud(track, frameOf(track, m)) &&
        gap != null && m >= gap.start - 0.011 && m <= gap.end + 0.011;
      const human = humanMarks[i];
      markResults.push({ scene: scene.id, inGap, deltaHumanMs: human != null ? (m - human) * 1000 : null });
    });

    // 3. human-gold agreement (export domain = working − trim).
    gold.lines.forEach((gl, li) => {
      const pl = result.tokenSync.lines[li];
      let prevGold: number | null = null;
      gl.tokens.forEach((gt, ti) => {
        const pt = pl?.tokens[ti];
        if (pt && pt.text === gt.text && pt.startSeconds != null) {
          const gapPrev = prevGold != null ? (gt.startSeconds - prevGold) * 1000 : null;
          rows.push({
            scene: scene.id, line: li, tok: ti, text: gt.text,
            deltaMs: (pt.startSeconds - trim - gt.startSeconds) * 1000,
            first: ti === 0, particle: PARTICLES.has(gt.text), singleChar: [...gt.text].length === 1,
            postPause: gapPrev != null && gapPrev > 350,
          });
        }
        prevGold = gt.startSeconds;
      });
    });

    const sceneRows = rows.filter((r) => r.scene === scene.id && !r.first).map((r) => Math.abs(r.deltaMs));
    perScene.push({
      scene: scene.id, tokens: lines.reduce((n, l) => n + l.tokens.length, 0),
      onsetMedianMs: median(sceneOffsets), onsetSdMs: sd(sceneOffsets), onsetN: sceneOffsets.length,
      humanNonFirstWithin100: pct(sceneRows, 100), flags: result.flags.length,
      alignSeconds: aligned.timings?.alignSeconds ?? null,
    });
    console.log(`${scene.id.padEnd(40)} tokens=${String(lines.reduce((n, l) => n + l.tokens.length, 0)).padStart(3)} onset med=${f0(median(sceneOffsets)).padStart(4)}ms sd=${f0(sd(sceneOffsets)).padStart(3)} (n=${sceneOffsets.length}) human≤100=${f1(pct(sceneRows, 100)).padStart(5)}% flags=${result.flags.length} ${((performance.now() - t0) / 1000).toFixed(1)}s`);
  }

  const sceneMedians = Object.values(perSceneOnset).filter((v) => v.length >= 3).map(median);
  const withinSceneSd = mean(Object.values(perSceneOnset).filter((v) => v.length >= 3).map(sd));
  const sceneToSceneSd = sd(sceneMedians);
  const marksIn = markResults.filter((m) => m.inGap).length;
  const markDeltas = markResults.map((m) => m.deltaHumanMs).filter((d): d is number => d != null);

  console.log(`\n=== onset metrics (primary) — shift ${(args.shiftSeconds * 1000).toFixed(0)} ms, ${scenes.length} scenes, readings on ${readingsUsed}/${tokensTotal} tokens ===`);
  console.log(`clean post-pause tokens: n=${onsetOffsets.length}  stamp − onset: median=${f0(median(onsetOffsets))} ms  p10=${f0(p95(onsetOffsets.map((x) => -x)) * -1)}  p90=${f0(p95(onsetOffsets))}`);
  console.log(`scene-to-scene sd of medians: ${f0(sceneToSceneSd)} ms (bar ≤ 25)   within-scene sd (mean): ${f0(withinSceneSd)} ms (bar ≤ 110)`);
  console.log(`\n=== derived line marks ===`);
  console.log(`inside silence gap: ${marksIn}/${markResults.length}   |mark − human mark|: median=${f0(median(markDeltas.map(Math.abs)))} ms  p95=${f0(p95(markDeltas.map(Math.abs)))} ms  signed median=${f0(median(markDeltas))}`);
  console.log(`monotonic violations: ${monotonicViolations}   flags: ${JSON.stringify(flagCounts)}`);
  console.log(`\n=== human-gold agreement (secondary; editors drift by session) ===`);
  console.log(classLine("all", rows));
  console.log(classLine("first-of-line", rows.filter((r) => r.first)));
  console.log(classLine("non-first", rows.filter((r) => !r.first)));
  console.log(classLine("particle", rows.filter((r) => r.particle)));
  console.log(classLine("single-char", rows.filter((r) => r.singleChar)));
  console.log(classLine("post-pause", rows.filter((r) => r.postPause)));
  console.log(classLine("mid-phrase", rows.filter((r) => !r.postPause && !r.first)));

  const pass = sceneToSceneSd <= 25 && withinSceneSd <= 110 && marksIn === markResults.length && monotonicViolations === 0;
  console.log(`\n${pass ? "PASS" : "FAIL"} (onset bar ${sceneToSceneSd <= 25 && withinSceneSd <= 110 ? "ok" : "MISSED"}, marks ${marksIn === markResults.length ? "ok" : "MISSED"}, monotonic ${monotonicViolations === 0 ? "ok" : "MISSED"})`);

  if (args.json) {
    writeFileSync(args.json, JSON.stringify({
      generatedAt: new Date().toISOString(), shiftMs: args.shiftSeconds * 1000, scenes: scenes.length,
      readings: { used: readingsUsed, total: tokensTotal },
      onset: { n: onsetOffsets.length, medianMs: median(onsetOffsets), sceneToSceneSdMs: sceneToSceneSd, withinSceneSdMs: withinSceneSd },
      marks: { inGap: marksIn, total: markResults.length, medianAbsDeltaHumanMs: median(markDeltas.map(Math.abs)) },
      monotonicViolations, flags: flagCounts,
      humanGold: Object.fromEntries([
        ["all", rows], ["first", rows.filter((r) => r.first)], ["nonFirst", rows.filter((r) => !r.first)],
        ["particle", rows.filter((r) => r.particle)], ["singleChar", rows.filter((r) => r.singleChar)],
        ["postPause", rows.filter((r) => r.postPause)], ["midPhrase", rows.filter((r) => !r.postPause && !r.first)],
      ].map(([k, rs]) => { const a = (rs as Row[]).map((r) => Math.abs(r.deltaMs)); return [k, { n: a.length, medianAbsMs: median(a), within100: pct(a, 100), within150: pct(a, 150), biasMs: median((rs as Row[]).map((r) => r.deltaMs)) }]; })),
      perScene, pass,
    }, null, 2));
    console.log(`wrote ${args.json}`);
  }
  process.exit(pass ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(2); });
