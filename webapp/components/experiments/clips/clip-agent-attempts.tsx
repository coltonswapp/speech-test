"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { BotIcon, ChevronDownIcon, ChevronRightIcon, ExternalLinkIcon, Loader2Icon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { formatApiError } from "@/lib/api-error";
import type { ClipAgentAttemptView } from "@/lib/clip-agent/store";
import type { ClipSnapshotDiff, LineChange } from "@/lib/clip-agent/diff";
import {
  CLIP_AGENT_TARGET_LABELS,
  type ClipAgentOutcome,
  type ClipAgentTarget,
} from "@/lib/clip-agent/schema";
import { formatUSD, STEP_LABELS } from "@/lib/experiments/clips/usage-cost";
import type { ClipUsageStep } from "@/lib/experiments/clips/types";
import { cn } from "@/lib/utils";

// Agent attempts on a learner report (docs/clip-agent-tickets-plan.md): Send
// to agent, and one card per attempt with what changed on the clip.

export const OUTCOME_LABELS: Record<ClipAgentOutcome, string> = {
  fixed: "Fixed",
  no_change_needed: "No change needed",
  needs_review: "Needs review",
  could_not_fix: "Couldn’t fix",
};

const FIELD_LABELS: Record<string, string> = {
  shiftSec: "Shift",
  feedEligible: "In feed",
  jlptLevel: "Level",
  deprecated: "Deprecated",
  durationSec: "Duration",
};

function formatTime(iso: string): string {
  return new Date(iso).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

const sec = (n: number | null) => (n === null ? "—" : `${n.toFixed(2)} s`);
const value = (v: string | number | boolean | null) =>
  v === null ? "—" : typeof v === "boolean" ? (v ? "yes" : "no") : v === "" ? "yes" : String(v);

/** The open report's latest finished attempt asked for a person's review. */
export function latestNeedsReview(attempts: ClipAgentAttemptView[]): ClipAgentAttemptView | null {
  const latest = attempts.find((a) => a.status === "done" || a.status === "working");
  return latest?.status === "done" && latest.outcome === "needs_review" ? latest : null;
}

export function SendToAgentButton({
  feedbackId,
  targets,
  disabled,
}: {
  feedbackId: string;
  targets: ClipAgentTarget[];
  disabled?: boolean;
}) {
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [target, setTarget] = useState<ClipAgentTarget | null>(null);
  const [instructions, setInstructions] = useState("");
  const send = useMutation({
    mutationFn: async (agent: ClipAgentTarget) => {
      const response = await fetch(`/api/experiments/clip-feedback/${feedbackId}/dispatch`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ agent, instructions: instructions.trim() || undefined }),
      });
      const json = await response.json().catch(() => null);
      if (!response.ok) throw new Error(formatApiError(json, response.status));
      return json as { attempt: ClipAgentAttemptView };
    },
    onSuccess: ({ attempt }) => {
      if (attempt.status === "failed") {
        toast.error(`Couldn’t reach ${attempt.agentLabel}: ${attempt.delivery?.error ?? "webhook failed"}`);
      } else {
        toast.success(`Sent to ${attempt.agentLabel}`);
        setOpen(false);
        setInstructions("");
      }
      void queryClient.invalidateQueries({ queryKey: ["clip-feedback"] });
    },
    onError: (error) => toast.error(error instanceof Error ? error.message : "Couldn’t send"),
  });

  if (targets.length === 0) return null;
  const picked = target && targets.includes(target) ? target : targets[0];

  return (
    <>
      <Button
        size="sm"
        variant="outline"
        disabled={disabled}
        onClick={() => {
          setTarget(picked);
          setOpen(true);
        }}
      >
        <BotIcon />
        Send to agent
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Send to agent</DialogTitle>
            <DialogDescription>
              The agent claims the report, fixes the clip following the playbook, and resolves it
              (or asks you to review). Studio keeps a before/after of the clip.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-wrap gap-2">
            {targets.map((t) => (
              <Button
                key={t}
                type="button"
                size="sm"
                variant={picked === t ? "default" : "outline"}
                onClick={() => setTarget(t)}
              >
                {CLIP_AGENT_TARGET_LABELS[t]}
              </Button>
            ))}
          </div>
          <Textarea
            value={instructions}
            onChange={(e) => setInstructions(e.target.value)}
            placeholder="Optional instructions (e.g. “line 3 is missing a word at the start”)"
            maxLength={2000}
            rows={3}
          />
          <DialogFooter>
            <Button
              disabled={send.isPending}
              onClick={() => send.mutate(picked)}
            >
              {send.isPending ? <Loader2Icon className="animate-spin" /> : null}
              Send to {CLIP_AGENT_TARGET_LABELS[picked]}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function LineChangeItem({ change }: { change: LineChange }) {
  if (change.kind === "added" || change.kind === "removed") {
    const added = change.kind === "added";
    return (
      <li className={cn("flex flex-col", added ? "text-emerald-700 dark:text-emerald-400" : "text-destructive")}>
        <span lang="ja">
          {added ? "+" : "−"} Line {(added ? change.afterIndex : change.beforeIndex) + 1}: {change.ja}
        </span>
        {change.en ? <span className="pl-3 text-xs opacity-80">{change.en}</span> : null}
      </li>
    );
  }
  return (
    <li className="flex flex-col gap-0.5">
      <span lang="ja">
        Line {change.afterIndex + 1}
        {change.afterIndex !== change.beforeIndex ? ` (was ${change.beforeIndex + 1})` : ""}: {change.ja}
      </span>
      <div className="flex flex-col gap-0.5 pl-3 text-xs text-muted-foreground">
        {change.jaBefore !== undefined ? (
          <span lang="ja">
            Text was: <span className="line-through">{change.jaBefore}</span>
          </span>
        ) : null}
        {change.en ? (
          <span>
            English: <span className="line-through">{change.en.before ?? "—"}</span> →{" "}
            <span className="text-foreground">{change.en.after ?? "—"}</span>
          </span>
        ) : null}
        {change.split ? (
          <span lang="ja">
            Split: <span className="line-through">{change.split.before}</span> →{" "}
            <span className="text-foreground">{change.split.after}</span>
          </span>
        ) : null}
        {change.readings?.map((r, i) => (
          <span key={i} lang="ja">
            Reading {r.text}: <span className="line-through">{r.before ?? "—"}</span> →{" "}
            <span className="text-foreground">{r.after ?? "—"}</span>
          </span>
        ))}
        {change.timing ? (
          <span className="tabular-nums">
            Timing: {sec(change.timing.before.start)}–{sec(change.timing.before.end)} →{" "}
            <span className="text-foreground">
              {sec(change.timing.after.start)}–{sec(change.timing.after.end)}
            </span>
          </span>
        ) : null}
      </div>
    </li>
  );
}

function DiffView({ diff }: { diff: ClipSnapshotDiff }) {
  if (diff.empty) return <p className="text-xs text-muted-foreground">Nothing a learner sees changed.</p>;
  return (
    <div className="flex flex-col gap-2 text-sm">
      {diff.fields.length > 0 ? (
        <ul className="flex flex-wrap gap-x-4 gap-y-1 text-xs">
          {diff.fields.map((f) => (
            <li key={f.field}>
              {FIELD_LABELS[f.field] ?? f.field}: <span className="line-through">{value(f.before)}</span> →{" "}
              {value(f.after)}
            </li>
          ))}
        </ul>
      ) : null}
      {diff.lines.length > 0 ? (
        <ul className="flex flex-col gap-1.5">
          {diff.lines.map((change, i) => (
            <LineChangeItem key={i} change={change} />
          ))}
        </ul>
      ) : null}
    </div>
  );
}

export const STATUS_VARIANT: Record<ClipAgentAttemptView["status"], "default" | "secondary" | "destructive" | "outline"> = {
  dispatched: "outline",
  working: "default",
  done: "secondary",
  failed: "destructive",
};

export function AttemptCard({ attempt }: { attempt: ClipAgentAttemptView }) {
  const [open, setOpen] = useState(attempt.outcome === "needs_review");
  const changes = attempt.diff ? attempt.diff.lines.length + attempt.diff.fields.length : 0;
  const [firstLine, ...rest] = (attempt.summary ?? "").split("\n");

  return (
    <div className="flex flex-col gap-1.5 rounded-md border border-border/60 bg-muted/30 p-2 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <BotIcon className="size-4 text-muted-foreground" />
        <span className="font-medium">{attempt.agentLabel}</span>
        <Badge variant={STATUS_VARIANT[attempt.status]}>
          {attempt.status === "done" && attempt.outcome ? OUTCOME_LABELS[attempt.outcome] : attempt.status}
        </Badge>
        {attempt.runUrl ? (
          <a
            href={attempt.runUrl}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
          >
            Run <ExternalLinkIcon className="size-3" />
          </a>
        ) : null}
        <span className="ml-auto text-xs text-muted-foreground tabular-nums" title={attempt.id}>
          {formatTime(attempt.finishedAt ?? attempt.startedAt ?? attempt.createdAt)}
        </span>
      </div>

      {attempt.instructions ? (
        <p className="text-xs text-muted-foreground">Asked: “{attempt.instructions}”</p>
      ) : null}
      {firstLine ? <p>{firstLine}</p> : null}
      {rest.join("\n").trim() ? (
        <p className="whitespace-pre-wrap text-xs text-muted-foreground">{rest.join("\n").trim()}</p>
      ) : null}
      {attempt.status === "dispatched" ? (
        <p className="text-xs text-muted-foreground">Waiting for the agent to pick it up.</p>
      ) : null}

      {attempt.diff || attempt.runs.length > 0 ? (
        <div className="flex flex-col gap-2">
          <button
            type="button"
            className="inline-flex items-center gap-1 self-start text-xs text-muted-foreground hover:text-foreground"
            onClick={() => setOpen((o) => !o)}
          >
            {open ? <ChevronDownIcon className="size-3" /> : <ChevronRightIcon className="size-3" />}
            {attempt.live ? "Changes so far" : "Changes while the attempt was open"}
            {attempt.diff ? ` · ${changes}` : ""}
            {attempt.runs.length ? ` · ${attempt.runs.length} run${attempt.runs.length === 1 ? "" : "s"}` : ""}
            {attempt.costUsd > 0 ? ` · ${formatUSD(attempt.costUsd)}` : ""}
          </button>
          {open ? (
            <div className="flex flex-col gap-2 border-l-2 border-border pl-3">
              {attempt.diff ? <DiffView diff={attempt.diff} /> : null}
              {attempt.runs.length > 0 ? (
                <ul className="flex flex-col gap-0.5 text-xs text-muted-foreground">
                  {attempt.runs.map((run, i) => (
                    <li key={i} className="tabular-nums">
                      {STEP_LABELS[run.step as ClipUsageStep] ?? run.step} · {run.model} ·{" "}
                      {(run.durationMs / 1000).toFixed(1)} s
                      {run.costUsd !== null ? ` · ${formatUSD(run.costUsd)}` : ""} · {formatTime(run.at)}
                    </li>
                  ))}
                </ul>
              ) : null}
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
