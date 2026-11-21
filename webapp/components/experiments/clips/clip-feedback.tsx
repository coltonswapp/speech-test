"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Loader2Icon, ThumbsDownIcon, ThumbsUpIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { EditorSection } from "@/components/experiments/clips/editor-section";
import {
  AttemptCard,
  latestNeedsReview,
  SendToAgentButton,
} from "@/components/experiments/clips/clip-agent-attempts";
import { RecoverIssueAttempt } from "@/components/content-issues/recover-issue-attempt";
import { formatApiError } from "@/lib/api-error";
import type { ClipRatingCounts } from "@/lib/clip-feedback/admin";
import type { ClipFeedbackWithAttempts } from "@/lib/clip-agent/store";
import { resolvedNoteFor, type ClipAgentTarget } from "@/lib/clip-agent/schema";
import {
  type ClipFeedbackReason,
  type ClipFeedbackStatus,
} from "@/lib/clip-feedback/schema";
import { cn } from "@/lib/utils";
import { CLIP_REASON_LABELS, ISSUE_STATUS_LABELS } from "@/lib/content-issues/labels";

// Learner feedback from the app (POST /api/client/clips/[id]/feedback): thumbs
// and "Report an issue". Content Issues links back to individual clips.

const REASON_LABELS = CLIP_REASON_LABELS;
const STATUS_LABELS = ISSUE_STATUS_LABELS;

type StatusFilter = ClipFeedbackStatus | "issues" | "all";

type ClipFeedbackRow = ClipFeedbackWithAttempts;

type FeedbackResponse = {
  rows: ClipFeedbackRow[];
  counts: ClipRatingCounts | null;
  openIssues: number;
  /** Agents "Send to agent" can reach (webhook env set). */
  agentTargets: ClipAgentTarget[];
};

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, init);
  if (!response.ok) {
    throw new Error(formatApiError(await response.json().catch(() => null), response.status));
  }
  return response.json() as Promise<T>;
}

const feedbackApi = {
  list: (params: { clipId?: string; status?: StatusFilter; reason?: ClipFeedbackReason | null }) => {
    const query = new URLSearchParams();
    if (params.clipId) query.set("clip_id", params.clipId);
    if (params.status) query.set("status", params.status);
    if (params.reason) query.set("reason", params.reason);
    return request<FeedbackResponse>(`/api/experiments/clip-feedback?${query}`);
  },
  setStatus: (id: string, status: ClipFeedbackStatus, note?: string) =>
    request<{ ok: true }>("/api/experiments/clip-feedback", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, status, note }),
    }),
};

function useSetStatus() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, status, note }: { id: string; status: ClipFeedbackStatus; note?: string }) =>
      feedbackApi.setStatus(id, status, note),
    onSuccess: (_, { status }) => {
      toast.success(status === "open" ? "Reopened" : `Marked ${STATUS_LABELS[status].toLowerCase()}`);
      void queryClient.invalidateQueries({ queryKey: ["clip-feedback"] });
    },
    onError: (error) => toast.error(error instanceof Error ? error.message : "Couldn’t update"),
  });
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

/** The reported line, with the picked word marked. */
function LineQuote({ row }: { row: ClipFeedbackRow }) {
  const line = row.line;
  if (!line) return null;
  const tokens = line.tokens ?? [];
  const picked = row.tokenPosition;
  return (
    <blockquote className="flex flex-col gap-0.5 border-l-2 border-border pl-3">
      <span className="text-xs text-muted-foreground">Line {line.index + 1} · {line.startSec.toFixed(2)} s</span>
      <span className="text-base" lang="ja">
        {picked != null && tokens.length > 0
          ? tokens.map((token) => (
              <span
                key={token.position}
                className={cn(
                  token.position === picked &&
                    "rounded bg-amber-200/70 px-0.5 font-medium dark:bg-amber-500/30"
                )}
              >
                {token.surface}
              </span>
            ))
          : line.textJP}
      </span>
      {line.textEN ? <span className="text-sm text-muted-foreground">{line.textEN}</span> : null}
      {picked != null ? (
        <span className="text-xs text-muted-foreground">
          Word:{" "}
          {(() => {
            const token = tokens.find((t) => t.position === picked);
            if (!token) return `#${picked}`;
            return token.reading && token.reading !== token.surface
              ? `${token.surface} (${token.reading})`
              : token.surface;
          })()}
        </span>
      ) : null}
    </blockquote>
  );
}

export function FeedbackItem({
  row,
  showClip,
  agentTargets,
}: {
  row: ClipFeedbackRow;
  showClip: boolean;
  agentTargets: ClipAgentTarget[];
}) {
  const setStatus = useSetStatus();
  const busy = setStatus.isPending;
  const isIssue = row.status !== null;
  const review = row.status === "open" ? latestNeedsReview(row.attempts) : null;
  const agentBusy = row.attempts.some((a) => a.status === "dispatched" || a.status === "working");

  return (
    <li className="flex flex-col gap-2 rounded-lg border border-border/60 p-3">
      <div className="flex flex-wrap items-center gap-2 text-sm">
        {row.kind === "rating" ? (
          row.rating === "up" ? (
            <ThumbsUpIcon className="size-4 text-emerald-600" aria-label="Thumbs up" />
          ) : (
            <ThumbsDownIcon className="size-4 text-destructive" aria-label="Thumbs down" />
          )
        ) : null}
        <Link className="font-medium hover:underline" href={`/content/issues/clip-${encodeURIComponent(row.id)}`}>
          {row.reason
            ? REASON_LABELS[row.reason]
            : row.rating === "up"
              ? "Good clip"
              : "Not a good clip"}
        </Link>
        {row.status ? (
          <Badge variant={row.status === "open" ? "destructive" : "secondary"}>
            {STATUS_LABELS[row.status]}
          </Badge>
        ) : null}
        {review ? <Badge className="bg-amber-500 text-white">Needs review</Badge> : null}
        {row.status === "open" && agentBusy ? <Badge variant="outline">Agent working</Badge> : null}
        <span className="ml-auto text-xs text-muted-foreground tabular-nums">
          {formatDate(row.createdAt)}
        </span>
      </div>

      {showClip ? (
        <Link
          href={`/experiments/clips/${row.clipId}`}
          className="text-sm underline-offset-2 hover:underline"
        >
          {row.clipTitle ?? row.clipId}{" "}
          <span className="text-xs text-muted-foreground">{row.clipId}</span>
        </Link>
      ) : null}

      <LineQuote row={row} />

      {row.note ? <p className="whitespace-pre-wrap text-sm">“{row.note}”</p> : null}

      <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
        <span title={row.userId}>From {row.userId.slice(0, 8)}</span>
        {row.appVersion ? (
          <span>
            · App {row.appVersion}
            {row.appBuild ? ` (${row.appBuild})` : ""}
          </span>
        ) : null}
        {row.resolvedAt ? <span>· Closed {formatDate(row.resolvedAt)}</span> : null}
        {isIssue ? (
          <span className="ml-auto flex gap-1">
            {row.status === "open" ? (
              <>
                {review ? (
                  <Button
                    size="sm"
                    disabled={busy}
                    onClick={() =>
                      setStatus.mutate({
                        id: row.id,
                        status: "resolved",
                        note: `Accepted: ${resolvedNoteFor(review.agent, review.id, review.summary ?? "")}`,
                      })
                    }
                  >
                    Accept fix
                  </Button>
                ) : null}
                <SendToAgentButton
                  feedbackId={row.id}
                  targets={agentTargets}
                  disabled={busy || agentBusy}
                />
                <Button
                  size="sm"
                  variant="outline"
                  disabled={busy}
                  onClick={() => setStatus.mutate({ id: row.id, status: "resolved" })}
                >
                  {busy ? <Loader2Icon className="animate-spin" /> : null}
                  Resolve
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={busy}
                  onClick={() => setStatus.mutate({ id: row.id, status: "wontfix" })}
                >
                  Won’t fix
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={busy}
                  onClick={() => setStatus.mutate({ id: row.id, status: "duplicate" })}
                >
                  Duplicate
                </Button>
              </>
            ) : (
              <Button
                size="sm"
                variant="ghost"
                disabled={busy}
                onClick={() => setStatus.mutate({ id: row.id, status: "open" })}
              >
                Reopen
              </Button>
            )}
          </span>
        ) : null}
      </div>

      {row.attempts.length > 0 ? (
        <div className="flex flex-col gap-1.5">
          {row.attempts.map((attempt) => (
            <AttemptCard key={attempt.id} attempt={attempt} />
          ))}
        </div>
      ) : null}
    </li>
  );
}

/** Clip editor: this clip's thumbs totals and every report and rating on it. */
export function ClipFeedbackSection({ clipId }: { clipId: string }) {
  const query = useQuery({
    queryKey: ["clip-feedback", "clip", clipId],
    queryFn: () => feedbackApi.list({ clipId, status: "all" }),
  });
  const counts = query.data?.counts;
  const rows = query.data?.rows ?? [];
  // Plain thumbs-ups say little on their own; the totals cover them.
  const shown = rows.filter((row) => row.status !== null || row.note || row.rating === "down");

  return (
    <EditorSection
      id="feedback"
      title="Learner feedback"
      summary={
        counts
          ? `👍 ${counts.up} · 👎 ${counts.down}${counts.openIssues ? ` · ${counts.openIssues} open` : ""}`
          : undefined
      }
      actions={
        <Link
          href="/content/issues?subject=clip"
          className="text-xs text-muted-foreground underline-offset-2 hover:underline"
        >
          All clips’ feedback
        </Link>
      }
    >
      {query.isPending ? (
        <Skeleton className="h-16 w-full" />
      ) : query.isError ? (
        <p className="text-sm text-destructive">{query.error.message}</p>
      ) : (
        <>
          <div className="flex items-center gap-4 text-sm">
            <span className="flex items-center gap-1.5">
              <ThumbsUpIcon className="size-4 text-emerald-600" /> {counts?.up ?? 0}
            </span>
            <span className="flex items-center gap-1.5">
              <ThumbsDownIcon className="size-4 text-destructive" /> {counts?.down ?? 0}
            </span>
            <span className="text-muted-foreground">
              {counts?.openIssues ? `${counts.openIssues} open issue${counts.openIssues === 1 ? "" : "s"}` : "No open issues"}
            </span>
          </div>
          {shown.length > 0 ? (
            <ul className="flex flex-col gap-2">
              {shown.map((row) => (
                <FeedbackItem
                  key={row.id}
                  row={row}
                  showClip={false}
                  agentTargets={query.data?.agentTargets ?? []}
                />
              ))}
            </ul>
          ) : (
            <p className="text-xs text-muted-foreground">
              No reports yet. Learners rate a clip in Clip Details and report a line from its
              breakdown screen (••• → Report an Issue).
            </p>
          )}
        </>
      )}
    </EditorSection>
  );
}

/** Uses the same cache as the editor so triage and attempt actions refresh the detail. */
export function ClipIssueDetail({ id }: { id: string }) {
  const query = useQuery({
    queryKey: ["clip-feedback", "detail", id],
    queryFn: () => request<FeedbackResponse>("/api/experiments/clip-feedback?id=" + encodeURIComponent(id)),
  });
  if (query.isPending) return <Skeleton className="h-40 w-full rounded-xl" />;
  if (query.isError) return <p role="alert" className="text-sm text-destructive">{query.error.message}</p>;
  const row = query.data.rows[0];
  if (!row) return <p className="text-sm text-muted-foreground">Report not found.</p>;
  const active = row.attempts.find((a) => a.status === "dispatched" || a.status === "working");
  return (
    <>
      <ul>
        <FeedbackItem row={row} showClip agentTargets={query.data.agentTargets} />
      </ul>
      {row.resolvedNote ? (
        <div className="rounded-xl border border-border/60 bg-muted/30 px-4 py-3 text-sm">
          <p className="mb-1 text-xs text-muted-foreground">
            Resolution note{row.resolvedAt ? ` · ${formatDate(row.resolvedAt)}` : ""}
          </p>
          <p className="whitespace-pre-wrap">{row.resolvedNote}</p>
        </div>
      ) : null}
      {row.status === "open" && !query.data.agentTargets.length ? (
        <p className="text-sm text-muted-foreground">
          No dispatch agents are available.{" "}
          <Link href="/settings/agents" className="text-foreground underline-offset-2 hover:underline">
            Configure agents
          </Link>
        </p>
      ) : null}
      {active ? (
        <RecoverIssueAttempt issueId={"clip-" + id} attemptId={active.id} onChange={() => void query.refetch()} />
      ) : null}
    </>
  );
}
