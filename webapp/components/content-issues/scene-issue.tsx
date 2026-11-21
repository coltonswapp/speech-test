"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { lessonReportCategoryLabels, lessonReportStatusLabels } from "@/lib/lesson-reports/types";
import type { sceneDetail } from "@/lib/content-issues/scenes";
import { RecoverIssueAttempt } from "./recover-issue-attempt";

export function SceneIssue({ report, configured }: {
  report: Awaited<ReturnType<typeof sceneDetail>>;
  configured: boolean;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const issueId = "scene-" + report.id;
  const apiHref = "/api/content/issues/" + issueId;

  async function dispatch() {
    setBusy(true);
    try {
      const response = await fetch(apiHref, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "dispatch", agent: "hana" }),
      });
      if (!response.ok) throw new Error((await response.json()).error);
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Dispatch failed");
    } finally {
      setBusy(false);
      router.refresh();
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardTitle role="heading" aria-level={2} className="wrap-anywhere text-base font-medium">{report.collectionId} / {report.scenarioId}</CardTitle>
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <Badge variant={report.status === "open" ? "destructive" : "secondary"}>{lessonReportStatusLabels[report.status]}</Badge>
            {report.categories.map(category => <Badge key={category} variant="outline">{lessonReportCategoryLabels[category]}</Badge>)}
            {report.createdAt && <time dateTime={report.createdAt}>{report.createdAt.slice(0, 10)}</time>}
          </div>
        </CardHeader>
        <CardContent className="flex flex-col gap-3 text-sm">
          <h2 className="font-medium">Learner evidence</h2>
          {report.note && <blockquote className="whitespace-pre-wrap wrap-anywhere border-l-2 pl-3">{report.note}</blockquote>}
          <div className="space-y-1 wrap-anywhere text-muted-foreground">
            <p>{[report.page, report.quizQuestionNumber != null && "Question " + report.quizQuestionNumber, report.focusTitle, report.sessionMode].filter(Boolean).join(" · ")}</p>
            {report.focusDetails.map((line, index) => <p key={index}>{line}</p>)}
            {report.pickedWord && <p>Picked word · <span lang="ja">{report.pickedWord}</span></p>}
            {report.playbackSeconds != null && <p>Playback position · {report.playbackSeconds.toFixed(2)} s</p>}
            {report.publishedVariantId && <p>Reported take · {report.publishedVariantId}</p>}
            {report.reportedContentHash && <p>Reported revision · {report.reportedContentHash}</p>}
          </div>
          <h2 className="border-t border-border/60 pt-3 font-medium">Actions</h2>
          <div className="flex flex-wrap items-center gap-2">
            <Link href={apiHref + "?published=1"} className={buttonVariants({ size: "sm", variant: "outline" })}>Inspect learner-visible export</Link>
            {report.status === "open" && (configured
              ? <Button size="sm" disabled={busy || Boolean(report.activeAttempt)} onClick={dispatch}>Send to Hana</Button>
              : <Link href="/settings/agents" className={buttonVariants({ size: "sm" })}>Configure Hana</Link>)}
          </div>
          {report.activeAttempt && (
            <RecoverIssueAttempt issueId={issueId} attemptId={report.activeAttempt} onChange={() => router.refresh()} />
          )}
          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle role="heading" aria-level={2} className="text-base font-medium">Attempts</CardTitle></CardHeader>
        <CardContent>
          {report.attempts.length === 0 ? (
            <p className="text-sm text-muted-foreground">No attempts yet.</p>
          ) : (
            <ul className="divide-y divide-border/60 rounded-xl border border-border/60">
              {report.attempts.map(attempt => (
                <li className="space-y-1 px-4 py-3 text-sm" key={attempt.id}>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-medium">{attempt.agent === "hana" ? "Hana" : attempt.agent}</span>
                    <Badge variant={attempt.status === "failed" ? "destructive" : "secondary"} className="capitalize">
                      {attempt.outcome?.replaceAll("_", " ") ?? attempt.status}
                    </Badge>
                    <time dateTime={attempt.createdAt} className="text-xs text-muted-foreground">{attempt.createdAt.slice(0, 10)}</time>
                  </div>
                  {attempt.summary && <p className="whitespace-pre-wrap wrap-anywhere text-muted-foreground">{attempt.summary}</p>}
                  {attempt.revision && <code className="wrap-anywhere text-xs">{attempt.revision}</code>}
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
