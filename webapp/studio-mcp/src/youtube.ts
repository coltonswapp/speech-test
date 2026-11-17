// YouTube lookups for adding Shorts to the clip queue, through yt-dlp on this
// machine (the same tool create_clip_from_youtube and run_clip_queue_batch
// already need). No API key: yt-dlp reads YouTube's public pages.
import { spawn } from "node:child_process";

const YOUTUBE_ID = /^[A-Za-z0-9_-]{11}$/;
const CHANNEL_ID = /^UC[A-Za-z0-9_-]{22}$/;
const HANDLE = /^@[A-Za-z0-9._-]{3,30}$/;

const YT_DLP = process.env.YT_DLP_PATH?.trim() || "yt-dlp";

type RunResult = { code: number; stdout: string; stderr: string };

function ytDlp(args: string[], timeoutMs: number): Promise<RunResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(YT_DLP, ["--no-warnings", "--ignore-config", ...args], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => child.kill("SIGTERM"), timeoutMs);
    child.stdout.on("data", (c: Buffer) => (stdout += c.toString()));
    child.stderr.on("data", (c: Buffer) => (stderr += c.toString()));
    child.on("error", (error) => {
      clearTimeout(timer);
      const missing = (error as NodeJS.ErrnoException).code === "ENOENT";
      reject(
        missing
          ? new Error(`yt-dlp not found (${YT_DLP}). Install it (brew install yt-dlp) or set YT_DLP_PATH.`)
          : error
      );
    });
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      if (signal === "SIGTERM") stderr += `\nERROR: yt-dlp timed out after ${Math.round(timeoutMs / 1000)} s`;
      resolve({ code: code ?? 1, stdout, stderr });
    });
  });
}

function lastError(stderr: string): string {
  const lines = stderr.split("\n").map((l) => l.trim()).filter(Boolean);
  const err = [...lines].reverse().find((l) => l.startsWith("ERROR:")) ?? lines.at(-1) ?? "yt-dlp failed";
  return err.replace(/^ERROR:\s*(\[[^\]]+\]\s*)?/, "");
}

// --- Parsing input ------------------------------------------------------------

/** A video id from an id or any watch / shorts / youtu.be / embed / live link; null if none. */
export function parseVideoInput(input: string): string | null {
  const trimmed = input.trim();
  if (YOUTUBE_ID.test(trimmed)) return trimmed;
  let url: URL;
  try {
    url = new URL(/^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`);
  } catch {
    return null;
  }
  const host = url.hostname.replace(/^(www|m|music)\./, "");
  if (host === "youtu.be") {
    const id = url.pathname.split("/").filter(Boolean)[0] ?? "";
    return YOUTUBE_ID.test(id) ? id : null;
  }
  if (host !== "youtube.com" && host !== "youtube-nocookie.com") return null;
  const v = url.searchParams.get("v");
  if (v) return YOUTUBE_ID.test(v) ? v : null;
  const [kind, id] = url.pathname.split("/").filter(Boolean);
  if (kind && ["shorts", "embed", "live", "v"].includes(kind) && id && YOUTUBE_ID.test(id)) return id;
  return null;
}

export type ChannelRef = { url: string; name?: string; channelId?: string; handle?: string };

/**
 * A channel page from a URL, @handle or UC… id. Returns null for anything
 * else (a plain name, which needs a search).
 */
export function parseChannelInput(input: string): ChannelRef | null {
  const trimmed = input.trim();
  if (HANDLE.test(trimmed)) return { url: `https://www.youtube.com/${trimmed}`, handle: trimmed };
  if (CHANNEL_ID.test(trimmed)) return { url: `https://www.youtube.com/channel/${trimmed}`, channelId: trimmed };
  if (!/youtube\.com\//i.test(trimmed)) return null;
  let url: URL;
  try {
    url = new URL(/^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`);
  } catch {
    return null;
  }
  const parts = url.pathname.split("/").filter(Boolean);
  const first = parts[0] ?? "";
  if (first.startsWith("@")) return { url: `https://www.youtube.com/${first}`, handle: first };
  if (first === "channel" && parts[1] && CHANNEL_ID.test(parts[1])) {
    return { url: `https://www.youtube.com/channel/${parts[1]}`, channelId: parts[1] };
  }
  if ((first === "c" || first === "user") && parts[1]) {
    return { url: `https://www.youtube.com/${first}/${parts[1]}` };
  }
  return null;
}

// --- Channels -----------------------------------------------------------------

export type ChannelMatch = {
  name: string;
  url: string;
  channelId: string | null;
  handle: string | null;
  subscribers: number | null;
};

type FlatEntry = Record<string, unknown>;
const str = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);
const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : null);

/** Channel search results for a name (YouTube's "Channels" filter). */
export async function searchChannels(query: string, limit = 8): Promise<ChannelMatch[]> {
  const url = `https://www.youtube.com/results?search_query=${encodeURIComponent(query)}&sp=EgIQAg%3D%3D`;
  const res = await ytDlp(["--flat-playlist", "-J", "--playlist-end", String(limit), url], 60_000);
  if (res.code !== 0 || !res.stdout.trim()) throw new Error(`Channel search failed: ${lastError(res.stderr)}`);
  const data = JSON.parse(res.stdout) as { entries?: FlatEntry[] };
  const matches: ChannelMatch[] = [];
  for (const e of data.entries ?? []) {
    const link = str(e.url) ?? str(e.channel_url);
    const channelId = str(e.channel_id) ?? (CHANNEL_ID.test(String(e.id ?? "")) ? String(e.id) : null);
    if (!link || !/\/(channel|@|c\/|user\/)/.test(link)) continue;
    const handle = str(e.uploader_id)?.startsWith("@") ? str(e.uploader_id) : (/\/(@[^/?#]+)/.exec(link)?.[1] ?? null);
    matches.push({
      name: str(e.title) ?? str(e.channel) ?? str(e.uploader) ?? link,
      url: link,
      channelId,
      handle,
      subscribers: num(e.channel_follower_count),
    });
  }
  return matches;
}

export type ChannelShorts = {
  channel: { name: string | null; channelId: string | null; url: string };
  /** Newest first, as the channel's Shorts tab lists them. */
  videoIds: string[];
};

/** The newest `limit` Shorts on a channel's Shorts tab (ids only). */
export async function listChannelShorts(channelUrl: string, limit: number): Promise<ChannelShorts> {
  const url = `${channelUrl.replace(/\/+$/, "")}/shorts`;
  const res = await ytDlp(["--flat-playlist", "-J", "--playlist-end", String(limit), url], 90_000);
  if (res.code !== 0 || !res.stdout.trim()) {
    throw new Error(`Couldn't list Shorts for ${channelUrl}: ${lastError(res.stderr)}`);
  }
  const data = JSON.parse(res.stdout) as FlatEntry & { entries?: FlatEntry[] };
  const ids = (data.entries ?? [])
    .map((e) => str(e.id))
    .filter((id): id is string => id !== null && YOUTUBE_ID.test(id));
  return {
    channel: {
      name: str(data.channel) ?? str(data.uploader) ?? str(data.title)?.replace(/ - Shorts$/, "") ?? null,
      channelId: str(data.channel_id),
      url: str(data.channel_url) ?? channelUrl,
    },
    videoIds: [...new Set(ids)],
  };
}

// --- Videos -------------------------------------------------------------------

export type VideoDetails = {
  videoId: string;
  title: string;
  channelName: string;
  channelId: string | null;
  channelUrl: string | null;
  durationSec: number | null;
  thumbnailUrl: string | null;
  uploadDate: string | null;
  width: number | null;
  height: number | null;
  availability: string | null;
  liveStatus: string | null;
  ageLimit: number;
  mediaType: string | null;
};

export type VideoLookup = { ok: true; details: VideoDetails } | { ok: false; videoId: string; error: string };

function toDetails(info: FlatEntry): VideoDetails | null {
  const videoId = str(info.id);
  if (!videoId || !YOUTUBE_ID.test(videoId)) return null;
  const uploadDate = str(info.upload_date);
  return {
    videoId,
    title: str(info.title) ?? "",
    channelName: str(info.channel) ?? str(info.uploader) ?? "Unknown channel",
    channelId: str(info.channel_id),
    channelUrl: str(info.channel_url),
    durationSec: num(info.duration),
    thumbnailUrl: str(info.thumbnail) ?? `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
    uploadDate: uploadDate && /^\d{8}$/.test(uploadDate)
      ? `${uploadDate.slice(0, 4)}-${uploadDate.slice(4, 6)}-${uploadDate.slice(6)}`
      : null,
    width: num(info.width),
    height: num(info.height),
    availability: str(info.availability),
    liveStatus: str(info.live_status),
    ageLimit: num(info.age_limit) ?? 0,
    mediaType: str(info.media_type),
  };
}

/**
 * Full details for each video (title, channel, length, size, availability).
 * One yt-dlp run per chunk, `parallel` runs at a time; a video yt-dlp can't
 * read comes back as { ok: false, error }. Order follows `videoIds`.
 */
export async function fetchVideoDetails(videoIds: string[], parallel = 6): Promise<VideoLookup[]> {
  const unique = [...new Set(videoIds)];
  const chunkSize = Math.max(1, Math.ceil(unique.length / parallel));
  const chunks: string[][] = [];
  for (let i = 0; i < unique.length; i += chunkSize) chunks.push(unique.slice(i, i + chunkSize));
  const found = new Map<string, VideoLookup>();
  await Promise.all(
    chunks.map(async (chunk) => {
      let res: RunResult;
      try {
        res = await ytDlp(
          [
            "-j",
            "--skip-download",
            "--ignore-errors",
            "--no-playlist",
            "--",
            ...chunk.map((id) => `https://www.youtube.com/watch?v=${id}`),
          ],
          30_000 + chunk.length * 15_000
        );
      } catch (error) {
        for (const id of chunk) {
          found.set(id, { ok: false, videoId: id, error: error instanceof Error ? error.message : String(error) });
        }
        return;
      }
      for (const line of res.stdout.split("\n")) {
        if (!line.trim().startsWith("{")) continue;
        try {
          const details = toDetails(JSON.parse(line) as FlatEntry);
          if (details) found.set(details.videoId, { ok: true, details });
        } catch {
          // a truncated line from a killed run; that id is reported below
        }
      }
      for (const line of res.stderr.split("\n")) {
        const m = /ERROR: \[youtube\] ([A-Za-z0-9_-]{11}): (.+)/.exec(line);
        if (m && !found.has(m[1]!)) found.set(m[1]!, { ok: false, videoId: m[1]!, error: m[2]!.trim() });
      }
      for (const id of chunk) {
        if (!found.has(id)) found.set(id, { ok: false, videoId: id, error: lastError(res.stderr) });
      }
    })
  );
  return unique.map((id) => found.get(id)!);
}

/**
 * Why a video can't go in the queue, from what YouTube says about it; null if
 * it can. "unavailable" = nobody can fetch it now; "ineligible" = it exists
 * but isn't something the queue makes clips from.
 */
export function videoProblem(d: VideoDetails): { kind: "unavailable" | "ineligible"; reason: string } | null {
  if (d.availability && !["public", "unlisted"].includes(d.availability)) {
    return { kind: "unavailable", reason: `Not public (${d.availability}).` };
  }
  if (d.liveStatus && ["is_live", "is_upcoming", "post_live"].includes(d.liveStatus)) {
    return { kind: "unavailable", reason: `Live stream (${d.liveStatus}); no finished video yet.` };
  }
  if (d.ageLimit >= 18) {
    return { kind: "unavailable", reason: "Age-restricted; the batch can't fetch its audio without sign-in." };
  }
  if (d.width !== null && d.height !== null && d.width >= d.height) {
    return {
      kind: "ineligible",
      reason: `Not vertical (${d.width}×${d.height}); queue clips are made as 9:16 Shorts. Use create_clip_from_youtube for landscape videos.`,
    };
  }
  return null;
}
