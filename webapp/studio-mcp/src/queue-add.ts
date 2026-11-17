// Adding YouTube Shorts to the clip queue: find candidates (from a channel or
// from links), review them, then add only the ids the caller approves.
// Adding never starts processing; run_clip_queue_batch does that.
//
// Lookups run yt-dlp on this machine (src/youtube.ts). Queue checks and the
// write go through Studio's POST /api/experiments/clip-queue, which is the
// one place that decides "already queued / already clipped / too long".
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { studioBaseUrl, studioFetch } from "./client.ts";
import { jobView, startJob, waitForJob, type JobContext } from "./jobs.ts";
import {
  fetchVideoDetails,
  listChannelShorts,
  parseChannelInput,
  parseVideoInput,
  searchChannels,
  videoProblem,
  type ChannelMatch,
  type ChannelRef,
  type VideoDetails,
} from "./youtube.ts";

type QueueSource = "channel-scan" | "link";

type ServerOutcome =
  | { videoId: string; result: "new" | "added"; flags: string[] }
  | { videoId: string; result: "duplicate" }
  | {
      videoId: string;
      result: "exists";
      status: "queued" | "skipped";
      note?: string;
      progress: "none" | "fetching" | "clipped";
      clipIds: string[];
    }
  | { videoId: string; result: "clipped"; clipIds: string[] }
  | { videoId: string; result: "fetching" }
  | { videoId: string; result: "rejected"; reason: string }
  | { videoId: string; result: "lost"; reason: string };

/** What review says about a candidate. Only "addable" ones are added. */
type Verdict =
  | "addable"
  | "in-queue"
  | "skipped-in-queue"
  | "already-clipped"
  | "fetching"
  | "unavailable"
  | "ineligible"
  | "duplicate-input"
  | "invalid-input";

type Candidate = {
  input?: string;
  videoId: string | null;
  verdict: Verdict;
  reason?: string;
  title?: string;
  channelName?: string;
  durationSec?: number | null;
  thumbnailUrl?: string | null;
  uploadDate?: string | null;
  /** Queue warnings (they don't block adding; the batch takes clean entries first). */
  warnings?: string[];
  clipIds?: string[];
  url?: string;
};

// Details from the last review, so add_to_clip_queue doesn't look them up
// again. Lost on restart; add then re-fetches.
const CACHE_MS = 12 * 60 * 60_000;
const reviewed = new Map<string, { details: VideoDetails; source: QueueSource; at: number }>();

function remember(details: VideoDetails, source: QueueSource) {
  reviewed.set(details.videoId, { details, source, at: Date.now() });
}

function cached(videoId: string) {
  const hit = reviewed.get(videoId);
  return hit && Date.now() - hit.at < CACHE_MS ? hit : undefined;
}

function queueItem(d: VideoDetails) {
  return {
    videoId: d.videoId,
    title: d.title || d.videoId,
    channelName: d.channelName,
    channelId: d.channelId,
    durationSec: d.durationSec,
  };
}

async function postQueue(details: VideoDetails[], source: QueueSource, dryRun: boolean) {
  if (details.length === 0) return new Map<string, ServerOutcome>();
  const { outcomes } = await studioFetch<{ outcomes: ServerOutcome[] }>("/api/experiments/clip-queue", {
    method: "POST",
    body: JSON.stringify({ items: details.map(queueItem), source, dryRun }),
    timeoutMs: 60_000,
  });
  return new Map(outcomes.map((o) => [o.videoId, o]));
}

function verdictFrom(o: ServerOutcome): Pick<Candidate, "verdict" | "reason" | "warnings" | "clipIds"> {
  switch (o.result) {
    case "new":
    case "added":
      return { verdict: "addable", ...(o.flags.length ? { warnings: o.flags } : {}) };
    case "exists":
      return {
        verdict: o.status === "skipped" ? "skipped-in-queue" : "in-queue",
        reason:
          o.status === "skipped"
            ? `Already in the queue, skipped${o.note ? `: ${o.note}` : ""}. Use set_clip_queue_status to restore it.`
            : `Already in the queue (progress: ${o.progress}).`,
        ...(o.clipIds.length ? { clipIds: o.clipIds } : {}),
      };
    case "clipped":
      return { verdict: "already-clipped", reason: "Already made into clips.", clipIds: o.clipIds };
    case "fetching":
      return { verdict: "fetching", reason: "Audio fetch already in progress for this video." };
    case "rejected":
      return { verdict: "ineligible", reason: o.reason };
    default:
      return { verdict: "duplicate-input", reason: "Listed twice." };
  }
}

function describe(d: VideoDetails): Partial<Candidate> {
  return {
    videoId: d.videoId,
    title: d.title,
    channelName: d.channelName,
    durationSec: d.durationSec,
    thumbnailUrl: d.thumbnailUrl,
    uploadDate: d.uploadDate,
    url: `https://www.youtube.com/shorts/${d.videoId}`,
  };
}

/** Look up and check videos (deduped ids, in order). Caches what it found. */
async function reviewIds(ctx: JobContext, ids: string[], source: QueueSource): Promise<Candidate[]> {
  ctx.log(`Looking up ${ids.length} video(s) with yt-dlp…`);
  const lookups = await fetchVideoDetails(ids);
  ctx.checkCancelled();
  const out = new Map<string, Candidate>();
  const fine: VideoDetails[] = [];
  for (const l of lookups) {
    if (!l.ok) {
      out.set(l.videoId, { videoId: l.videoId, verdict: "unavailable", reason: l.error });
      continue;
    }
    remember(l.details, source);
    const problem = videoProblem(l.details);
    if (problem) out.set(l.details.videoId, { ...describe(l.details), videoId: l.details.videoId, verdict: problem.kind, reason: problem.reason });
    else fine.push(l.details);
  }
  ctx.log(`Checking ${fine.length} against the queue and existing clips…`);
  const outcomes = await postQueue(fine, source, true);
  for (const d of fine) {
    const o = outcomes.get(d.videoId);
    out.set(d.videoId, {
      ...describe(d),
      videoId: d.videoId,
      ...(o ? verdictFrom(o) : { verdict: "ineligible", reason: "Studio gave no answer for this video." }),
    });
  }
  return ids.map((id) => out.get(id)!);
}

function summary(candidates: Candidate[]) {
  const counts: Record<string, number> = {};
  for (const c of candidates) counts[c.verdict] = (counts[c.verdict] ?? 0) + 1;
  return {
    counts,
    addableIds: candidates.filter((c) => c.verdict === "addable").map((c) => c.videoId!),
    next: "Pick ids from addableIds (check warnings) and call add_to_clip_queue { videoIds }. Adding doesn't process anything; run_clip_queue_batch does.",
  };
}

const norm = (s: string) => s.toLowerCase().replace(/^@/, "").replace(/\s+/g, "");

type Resolved =
  | { ok: true; channel: ChannelRef; resolvedBy: string; otherMatches?: ChannelMatch[] }
  | { ok: false; reason: string; matches: ChannelMatch[] };

async function resolveChannel(input: string): Promise<Resolved> {
  const direct = parseChannelInput(input);
  if (direct) return { ok: true, channel: direct, resolvedBy: "url-or-handle" };
  const matches = await searchChannels(input);
  if (matches.length === 0) return { ok: false, reason: `No YouTube channel found for "${input}".`, matches };
  const exact = matches.filter(
    (m) => norm(m.name) === norm(input) || (m.handle !== null && norm(m.handle) === norm(input))
  );
  if (exact.length === 1) {
    const pick = exact[0]!;
    const others = matches.filter((m) => m !== pick);
    return {
      ok: true,
      channel: { url: pick.url, name: pick.name, channelId: pick.channelId ?? undefined, handle: pick.handle ?? undefined },
      resolvedBy: "search: the only result whose name or handle matches exactly",
      ...(others.length ? { otherMatches: others } : {}),
    };
  }
  return {
    ok: false,
    reason:
      exact.length > 1
        ? `${exact.length} channels are named "${input}". Pass one of their URLs or handles.`
        : `No channel is named exactly "${input}". Pass the URL or handle of the one you mean.`,
    matches: exact.length > 1 ? exact : matches,
  };
}

const waitSecondsSchema = z
  .number()
  .int()
  .min(0)
  .max(55)
  .default(50)
  .describe("Seconds to wait before returning (≤55). The job keeps running; poll get_clip_job.");

export function registerQueueAddTools(server: McpServer) {
  server.registerTool(
    "find_channel_shorts",
    {
      title: "Find a channel's recent Shorts for the queue",
      description: [
        "Candidates for the clip queue from one YouTube channel's Shorts tab, newest first. Doesn't add anything: review the candidates, then call add_to_clip_queue with the ids you want.",
        "channel: URL (youtube.com/@x, /channel/UC…, /c/x, /user/x; a tab like /shorts is fine), @handle, UC… id, or a name. A name is searched; it's used only if exactly one result's name or handle matches exactly (others come back as otherMatches). Otherwise you get resolved:false with the matches to choose from: call again with that channel's URL.",
        "count: how many Shorts to review. newOnly (default true): keep scanning older Shorts (up to scanLimit) until count are addable, so already queued/clipped/unavailable ones don't use up the count; they are still listed.",
        "Each candidate: videoId, title, channelName, durationSec, thumbnailUrl, uploadDate, verdict (addable / in-queue / skipped-in-queue / already-clipped / fetching / unavailable / ineligible), reason, warnings (queue warnings like under 20 s or music title; they don't block adding).",
        "Uses yt-dlp on this machine; about 2–5 s per Short. Runs as a job.",
      ].join("\n"),
      inputSchema: {
        channel: z.string().min(1),
        count: z.number().int().min(1).max(30).default(10),
        newOnly: z.boolean().default(true),
        scanLimit: z.number().int().min(1).max(150).optional().describe("Most Shorts to look at (default 3 × count, max 150)."),
        waitSeconds: waitSecondsSchema,
      },
    },
    async ({ channel, count, newOnly, scanLimit, waitSeconds }) => {
      const job = startJob("find-shorts", { channel, count, newOnly }, async (ctx) => {
        ctx.log(`Resolving channel "${channel}"…`);
        const resolved = await resolveChannel(channel);
        if (!resolved.ok) return { resolved: false, reason: resolved.reason, matches: resolved.matches };
        const limit = newOnly ? (scanLimit ?? Math.min(150, count * 3)) : count;
        ctx.log(`Listing up to ${limit} Shorts from ${resolved.channel.url}…`);
        const shorts = await listChannelShorts(resolved.channel.url, limit);
        const candidates: Candidate[] = [];
        let addable = 0;
        // Small batches, so newOnly stops once it has enough.
        for (let i = 0; i < shorts.videoIds.length; i += 10) {
          ctx.checkCancelled();
          const need = newOnly ? count - addable : count - candidates.length;
          if (need <= 0) break;
          const batch = shorts.videoIds.slice(i, i + (newOnly ? 10 : Math.min(10, need)));
          for (const c of await reviewIds(ctx, batch, "channel-scan")) {
            if (newOnly && addable >= count) break;
            candidates.push(c);
            if (c.verdict === "addable") addable++;
          }
        }
        return {
          resolved: true,
          resolvedBy: resolved.resolvedBy,
          channel: { ...shorts.channel, handle: resolved.channel.handle ?? null },
          ...(resolved.otherMatches ? { otherMatches: resolved.otherMatches } : {}),
          shortsListed: shorts.videoIds.length,
          ...(shorts.videoIds.length === 0 ? { note: "This channel has no Shorts." } : {}),
          ...(newOnly && addable < count && shorts.videoIds.length > 0
            ? { note: `Only ${addable} addable among the ${candidates.length} Shorts reviewed (scanLimit ${limit}).` }
            : {}),
          candidates,
          ...summary(candidates),
        };
      });
      await waitForJob(job, waitSeconds);
      return { content: [{ type: "text" as const, text: JSON.stringify(jobView(job, 10), null, 2) }] };
    }
  );

  server.registerTool(
    "review_youtube_videos",
    {
      title: "Review YouTube links for the queue",
      description: [
        "Candidates for the clip queue from YouTube links or ids (watch, shorts, youtu.be, embed, live; typically 5–10). Doesn't add anything: review, then call add_to_clip_queue with the ids you want.",
        "Each input comes back in order with verdict: addable, in-queue, skipped-in-queue, already-clipped, fetching (audio being fetched), unavailable (deleted, private, live, age-restricted), ineligible (not vertical, or over 120 s), duplicate-input (same video listed earlier), invalid-input (not a YouTube video link); plus title, channelName, durationSec, thumbnailUrl, uploadDate, reason and warnings.",
        "Uses yt-dlp on this machine. Runs as a job.",
      ].join("\n"),
      inputSchema: {
        videos: z.array(z.string().min(1)).min(1).max(20),
        waitSeconds: waitSecondsSchema,
      },
    },
    async ({ videos, waitSeconds }) => {
      const job = startJob("review-links", { videos: videos.length }, async (ctx) => {
        const parsed = videos.map((input) => ({ input, videoId: parseVideoInput(input) }));
        const seen = new Set<string>();
        const unique: string[] = [];
        for (const p of parsed) {
          if (p.videoId && !seen.has(p.videoId)) {
            seen.add(p.videoId);
            unique.push(p.videoId);
          }
        }
        const reviewedById = new Map(
          (unique.length ? await reviewIds(ctx, unique, "link") : []).map((c) => [c.videoId!, c])
        );
        const firstIndex = new Map<string, number>();
        const candidates: Candidate[] = parsed.map((p, i) => {
          if (!p.videoId) {
            return { input: p.input, videoId: null, verdict: "invalid-input", reason: "Not a YouTube video id or link." };
          }
          if (firstIndex.has(p.videoId)) {
            return {
              input: p.input,
              videoId: p.videoId,
              verdict: "duplicate-input",
              reason: `Same video as input #${firstIndex.get(p.videoId)! + 1}.`,
            };
          }
          firstIndex.set(p.videoId, i);
          return { input: p.input, ...reviewedById.get(p.videoId)! };
        });
        return { candidates, ...summary(candidates) };
      });
      await waitForJob(job, waitSeconds);
      return { content: [{ type: "text" as const, text: JSON.stringify(jobView(job, 10), null, 2) }] };
    }
  );

  server.registerTool(
    "add_to_clip_queue",
    {
      title: "Add approved videos to the clip queue",
      description: [
        "Add the video ids you approved (from find_channel_shorts / review_youtube_videos) to the clip queue as queued. Does NOT start processing: run run_clip_queue_batch afterwards.",
        "Safe to retry with the same ids: ones already in the queue are reported (in-queue / skipped-in-queue) and left as they are. Ids not reviewed in this MCP session are looked up again first. Unavailable, non-vertical, over-120 s, already-clipped and in-fetch videos are refused with a reason. Each id comes back with result: added, or a refusal verdict; lost means a simultaneous queue write dropped it: retry.",
        "source defaults to channel-scan for ids found by find_channel_shorts, link otherwise.",
      ].join("\n"),
      inputSchema: {
        videoIds: z.array(z.string().regex(/^[A-Za-z0-9_-]{11}$/)).min(1).max(50),
        source: z.enum(["channel-scan", "link"]).optional(),
      },
    },
    async ({ videoIds, source }) => {
      try {
        const ids = [...new Set(videoIds)];
        const results = new Map<string, Record<string, unknown>>();
        const toFetch = ids.filter((id) => !cached(id));
        if (toFetch.length) {
          for (const l of await fetchVideoDetails(toFetch)) {
            if (l.ok) remember(l.details, source ?? "link");
            else results.set(l.videoId, { videoId: l.videoId, result: "unavailable", reason: l.error });
          }
        }
        const bySource = new Map<QueueSource, VideoDetails[]>();
        for (const id of ids) {
          if (results.has(id)) continue;
          const hit = cached(id)!;
          const problem = videoProblem(hit.details);
          if (problem) {
            results.set(id, { videoId: id, title: hit.details.title, result: problem.kind, reason: problem.reason });
            continue;
          }
          const s = source ?? hit.source;
          bySource.set(s, [...(bySource.get(s) ?? []), hit.details]);
        }
        const failures: string[] = [];
        for (const [s, details] of bySource) {
          try {
            const outcomes = await postQueue(details, s, false);
            for (const d of details) {
              const o = outcomes.get(d.videoId);
              if (o?.result === "added") results.set(d.videoId, { videoId: d.videoId, title: d.title, result: "added", ...(o.flags.length ? { warnings: o.flags } : {}) });
              else if (o?.result === "lost") results.set(d.videoId, { videoId: d.videoId, title: d.title, result: "lost", reason: o.reason });
              else if (o) {
                const v = verdictFrom(o);
                results.set(d.videoId, { videoId: d.videoId, title: d.title, result: v.verdict, reason: v.reason, ...(v.clipIds ? { clipIds: v.clipIds } : {}) });
              } else results.set(d.videoId, { videoId: d.videoId, title: d.title, result: "error", reason: "Studio gave no answer for this video." });
            }
          } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            failures.push(message);
            for (const d of details) {
              results.set(d.videoId, { videoId: d.videoId, title: d.title, result: "error", reason: `Queue write failed: ${message}. Nothing for this id was confirmed; retrying is safe.` });
            }
          }
        }
        const list = ids.map((id) => results.get(id)!);
        const added = list.filter((r) => r.result === "added").map((r) => r.videoId as string);
        const retry = list.filter((r) => r.result === "lost" || r.result === "error").map((r) => r.videoId as string);
        return {
          ...(failures.length && added.length === 0 ? { isError: true } : {}),
          content: [
            {
              type: "text" as const,
              text: JSON.stringify(
                {
                  added,
                  notAdded: list.filter((r) => r.result !== "added").length,
                  ...(retry.length ? { retry, retryHint: "Call add_to_clip_queue again with these ids." } : {}),
                  results: list,
                  next: added.length
                    ? "Nothing is processing yet. Run run_clip_queue_batch (e.g. { channel } for these, or dryRun first) to make clips."
                    : undefined,
                  queue: `${studioBaseUrl()}/experiments/clips/queue`,
                },
                null,
                2
              ),
            },
          ],
        };
      } catch (error) {
        return { isError: true, content: [{ type: "text" as const, text: error instanceof Error ? error.message : String(error) }] };
      }
    }
  );
}
