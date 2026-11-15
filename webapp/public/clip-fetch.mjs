// Downloads a clip's audio from YouTube and attaches it to the clip whose
// details were entered in Studio (Experiments → Clip transcripts → New clip).
//
// Studio serves this file (it is public: no secrets in it) so the command it
// shows runs from any folder, with nothing but Node installed:
//
//   curl -fsSL https://<studio>/clip-fetch.mjs | node --input-type=module - '<link>'
//
// From the repo, `pnpm clip:fetch '<link>'` runs the same file. Plain
// JavaScript on Node built-ins only: it is piped straight into node.
//
// The link is https://<studio>/hooks/clip-upload/<clip id>#<one-time token>.
// Several links (a batch from the clip queue) are fetched one after another.
// It carries everything: the script asks Studio for the video and range,
// downloads just that section with yt-dlp, converts it to the mono 16 kHz WAV
// the pipeline expects, uploads it straight to R2 with a signed URL, and tells
// Studio to create the clip. No env vars or login; the token is the access.
//
// Needs yt-dlp and ffmpeg on PATH (brew install yt-dlp ffmpeg). YouTube is
// only ever contacted from this machine, never from Studio.
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

class Stop extends Error {}

/** Seconds as yt-dlp section text: at most 3 decimals, no trailing zeros. */
function sectionTime(seconds) {
  return String(Number(seconds.toFixed(3)));
}

function requireTool(name) {
  const probe = spawnSync(name, ["-version"], { stdio: "ignore" });
  if (probe.error) {
    throw new Stop(`${name} isn’t installed. Run: brew install yt-dlp ffmpeg`);
  }
}

function run(command, args) {
  const result = spawnSync(command, args, { stdio: "inherit" });
  if (result.error) throw new Stop(`Couldn’t run ${command}: ${result.error.message}`);
  if (result.status !== 0) throw new Stop(`${command} failed (exit ${result.status}).`);
}

async function errorText(response) {
  const body = await response.json().catch(() => null);
  return typeof body?.error === "string" ? body.error : `HTTP ${response.status}`;
}

/** 44-byte header + samples: the same shape Studio's browser encoder writes. */
function pcm16MonoWav(pcm, sampleRate) {
  const header = Buffer.alloc(44);
  header.write("RIFF", 0, "ascii");
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write("WAVE", 8, "ascii");
  header.write("fmt ", 12, "ascii");
  header.writeUInt32LE(16, 16); // fmt chunk size
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * 2, 28); // byte rate
  header.writeUInt16LE(2, 32); // block align
  header.writeUInt16LE(16, 34); // bits per sample
  header.write("data", 36, "ascii");
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

async function main() {
  const links = process.argv.slice(2);
  if (links.length === 0) {
    throw new Stop("No clip link given. Copy the whole command from Studio.");
  }
  requireTool("yt-dlp");
  requireTool("ffmpeg");
  if (links.length === 1) {
    await fetchClip(links[0]);
    return;
  }
  // A batch from the clip queue: one failure (a deleted video, say) doesn't
  // stop the rest.
  const failed = [];
  for (const [index, link] of links.entries()) {
    console.log(`\n[${index + 1}/${links.length}]`);
    try {
      await fetchClip(link);
    } catch (error) {
      const message = error instanceof Stop ? error.message : String(error?.message ?? error);
      console.error(message);
      failed.push(message);
    }
  }
  console.log(`\nDone: ${links.length - failed.length} of ${links.length} clips made.`);
  if (failed.length > 0) throw new Stop(`${failed.length} failed; see above.`);
}

async function fetchClip(link) {
  let hook;
  try {
    hook = new URL(link);
  } catch {
    throw new Stop("That isn’t a Studio clip link. Copy the whole command from Studio.");
  }
  const token = hook.hash.slice(1);
  hook.hash = "";
  if (!token || !hook.pathname.includes("/hooks/clip-upload/")) {
    throw new Stop("That isn’t a Studio clip link. Copy the whole command from Studio.");
  }
  const headers = { Authorization: `Bearer ${token}` };

  const ticketResponse = await fetch(hook, { headers });
  if (!ticketResponse.ok) throw new Stop(await errorText(ticketResponse));
  const ticket = await ticketResponse.json();
  const range =
    ticket.endSec === null
      ? "whole video"
      : `${sectionTime(ticket.startSec)}–${sectionTime(ticket.endSec)} s`;
  console.log(`Clip ${ticket.id}: video ${ticket.videoId}, ${range}`);

  const dir = mkdtempSync(path.join(tmpdir(), "clip-fetch-"));
  try {
    // Same download Studio's copy-paste command has always used: a section
    // that starts after 0:00 is cut exactly at its start.
    const section =
      ticket.endSec === null
        ? []
        : [
            "--download-sections",
            `*${sectionTime(ticket.startSec)}-${sectionTime(ticket.endSec)}`,
            ...(ticket.startSec > 0 ? ["--force-keyframes-at-cuts"] : []),
          ];
    run("yt-dlp", [
      "-f",
      "bestaudio",
      "-x",
      "--audio-format",
      "m4a",
      "--no-playlist",
      ...section,
      "-o",
      path.join(dir, "source.%(ext)s"),
      `https://www.youtube.com/watch?v=${ticket.videoId}`,
    ]);
    const source = readdirSync(dir).find((name) => name.startsWith("source."));
    if (!source) throw new Stop("yt-dlp finished but left no audio file.");

    const pcmPath = path.join(dir, "clip.pcm");
    run("ffmpeg", [
      "-v",
      "error",
      "-y",
      "-i",
      path.join(dir, source),
      "-vn",
      "-ac",
      "1",
      "-ar",
      String(ticket.sampleRate),
      "-f",
      "s16le",
      "-acodec",
      "pcm_s16le",
      pcmPath,
    ]);
    let pcm = readFileSync(pcmPath);
    const bytesPerSecond = ticket.sampleRate * 2;
    // A section can come back a few frames long; never keep more than was asked for.
    if (ticket.endSec !== null) {
      const wanted = Math.round((ticket.endSec - ticket.startSec) * ticket.sampleRate) * 2;
      if (pcm.length > wanted) pcm = pcm.subarray(0, wanted);
    }
    const seconds = pcm.length / bytesPerSecond;
    if (seconds > ticket.maxSeconds) {
      throw new Stop(
        `The audio is ${Math.round(seconds / 60)} minutes; the limit is ${Math.round(ticket.maxSeconds / 60)}. ` +
          "In Studio, discard this clip and enter a shorter range."
      );
    }
    console.log(`Uploading ${seconds.toFixed(1)} s of audio…`);

    const upload = await fetch(ticket.uploadUrl, {
      method: "PUT",
      headers: { "Content-Type": "audio/wav" },
      body: pcm16MonoWav(pcm, ticket.sampleRate),
    });
    if (!upload.ok) throw new Stop(`Upload failed (HTTP ${upload.status}).`);

    // Studio checks the audio and makes the clip, or cuts long audio into clips at pauses.
    console.log("Creating…");
    const finalize = await fetch(hook, { method: "POST", headers });
    if (!finalize.ok) throw new Stop(await errorText(finalize));
    const made = await finalize.json();
    const ids = Array.isArray(made.ids) ? made.ids : [ticket.id];
    if (ids.length === 1) {
      console.log(`Created ${ids[0]}. ${hook.origin}/experiments/clips/${ids[0]}`);
    } else {
      console.log(
        `Created ${ids.length} clips (${ids[0]} … ${ids[ids.length - 1]}). ` +
          `${hook.origin}/experiments/clips/video/${ticket.videoId}`
      );
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  if (error instanceof Stop) console.error(`\n${error.message}`);
  else console.error(error);
  process.exit(1);
});
