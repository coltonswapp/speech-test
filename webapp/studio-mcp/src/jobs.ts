// Background jobs for slow clip work (pipeline steps take up to minutes; a
// queue batch can take half an hour). MCP hosts time out long tool calls, so
// tools start a job, optionally wait a little, and hand back a job id that
// get_clip_job polls.
//
// Jobs live in this server process only: restarting the MCP server forgets
// them. The work itself is saved in Studio as each step finishes, so a lost
// job is re-run with run_clip_steps mode "missing".
import { spawn, type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";

export type JobStatus = "running" | "succeeded" | "failed" | "cancelled";

export type Job = {
  id: string;
  kind: string;
  /** What was asked for, for the agent's own bookkeeping. */
  params: unknown;
  status: JobStatus;
  startedAt: string;
  finishedAt?: string;
  /** Last lines of progress (script output or step progress). */
  log: string[];
  /** Structured outcome, set when the job finishes. */
  result?: unknown;
  error?: string;
  child?: ChildProcess;
  cancelRequested?: boolean;
  done: Promise<void>;
};

const MAX_LOG_LINES = 400;
const MAX_FINISHED_JOBS = 50;
const jobs = new Map<string, Job>();

export class JobCancelled extends Error {
  constructor() {
    super("Cancelled");
  }
}

export type JobContext = {
  log: (line: string) => void;
  /** Throws JobCancelled once cancel_clip_job was called; check between units of work. */
  checkCancelled: () => void;
  isCancelled: () => boolean;
  setChild: (child: ChildProcess) => void;
};

function prune() {
  const finished = [...jobs.values()].filter((j) => j.status !== "running");
  for (const job of finished.slice(0, Math.max(0, finished.length - MAX_FINISHED_JOBS))) {
    jobs.delete(job.id);
  }
}

export function startJob(
  kind: string,
  params: unknown,
  run: (ctx: JobContext) => Promise<unknown>
): Job {
  prune();
  const id = `${kind}-${randomBytes(3).toString("hex")}`;
  const job = { id, kind, params, status: "running", startedAt: new Date().toISOString(), log: [] } as unknown as Job;
  const ctx: JobContext = {
    log: (line) => {
      const stamped = `${new Date().toISOString().slice(11, 19)} ${line}`;
      job.log.push(stamped);
      if (job.log.length > MAX_LOG_LINES) job.log.splice(0, job.log.length - MAX_LOG_LINES);
    },
    checkCancelled: () => {
      if (job.cancelRequested) throw new JobCancelled();
    },
    isCancelled: () => Boolean(job.cancelRequested),
    setChild: (child) => {
      job.child = child;
    },
  };
  job.done = (async () => {
    try {
      job.result = await run(ctx);
      job.status = job.cancelRequested ? "cancelled" : "succeeded";
    } catch (error) {
      job.status = error instanceof JobCancelled || job.cancelRequested ? "cancelled" : "failed";
      job.error = error instanceof Error ? error.message : String(error);
    } finally {
      job.finishedAt = new Date().toISOString();
      job.child = undefined;
    }
  })();
  jobs.set(id, job);
  return job;
}

export function getJob(id: string): Job | undefined {
  return jobs.get(id);
}

export function listJobs(): Job[] {
  return [...jobs.values()].reverse();
}

export function cancelJob(id: string): Job | undefined {
  const job = jobs.get(id);
  if (!job || job.status !== "running") return job;
  job.cancelRequested = true;
  job.child?.kill("SIGTERM");
  return job;
}

/** Waits up to `seconds` for the job to finish (0 = don't wait). */
export async function waitForJob(job: Job, seconds: number): Promise<void> {
  if (seconds <= 0 || job.status !== "running") return;
  await Promise.race([job.done, new Promise((resolve) => setTimeout(resolve, seconds * 1000))]);
}

export function jobView(job: Job, logLines = 40) {
  const ms = (job.finishedAt ? Date.parse(job.finishedAt) : Date.now()) - Date.parse(job.startedAt);
  return {
    jobId: job.id,
    kind: job.kind,
    status: job.status,
    params: job.params,
    startedAt: job.startedAt,
    finishedAt: job.finishedAt ?? null,
    elapsedSec: Math.round(ms / 1000),
    ...(job.error ? { error: job.error } : {}),
    ...(job.result !== undefined ? { result: job.result } : {}),
    logTail: logLines > 0 ? job.log.slice(-logLines) : [],
    ...(job.status === "running"
      ? { hint: `Still running. Poll get_clip_job { jobId: "${job.id}", waitSeconds: 50 }.` }
      : {}),
  };
}

/**
 * Runs a command, feeding each output line to `onLine`. Resolves with the
 * exit code (non-zero is not thrown: scripts report partial failures).
 */
export function runCommand(
  ctx: JobContext,
  command: string,
  args: string[],
  options: { cwd: string; env?: NodeJS.ProcessEnv; onLine?: (line: string) => void }
): Promise<number> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: { ...process.env, ...options.env },
      stdio: ["ignore", "pipe", "pipe"],
    });
    ctx.setChild(child);
    let partial = "";
    const forward = (chunk: Buffer) => {
      const text = partial + chunk.toString();
      const lines = text.split(/\r?\n|\r/);
      partial = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.trim()) continue;
        (options.onLine ?? ctx.log)(line);
      }
    };
    child.stdout.on("data", forward);
    child.stderr.on("data", forward);
    child.on("error", reject);
    child.on("close", (code) => {
      if (partial.trim()) (options.onLine ?? ctx.log)(partial);
      resolve(code ?? 1);
    });
  });
}
