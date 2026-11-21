"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type ReactNode } from "react";
import { BotIcon, ExternalLinkIcon, Loader2Icon, SendIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { OUTCOME_LABELS, STATUS_VARIANT } from "@/components/experiments/clips/clip-agent-attempts";
import { LocalTime } from "./local-time";
import { RecoverIssueAttempt } from "./recover-issue-attempt";
import type { sceneDetail } from "@/lib/content-issues/scenes";

type Report = Awaited<ReturnType<typeof sceneDetail>>;

/** A bordered block with a small heading, matching Studio's section cards. */
export function IssuePanel({ title, actions, children }: { title: ReactNode; actions?: ReactNode; children: ReactNode }) {
  return (
    <section className="rounded-xl border border-border/60">
      <div className="flex flex-wrap items-center gap-2 border-b border-border/60 px-4 py-3">
        <h2 className="mr-auto text-sm font-medium">{title}</h2>
        {actions}
      </div>
      <div className="flex flex-col gap-3 p-4">{children}</div>
    </section>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="min-w-0 text-sm break-words">{children}</dd>
    </>
  );
}

const LINE_KEYS = new Set(["speaker", "japanese", "english"]);

/** The app sends focus details as "Label: value" lines; split them so they read as fields. */
function parseFocusDetails(details: string[]) {
  const line: Record<string, string> = {};
  const fields: { label: string; value: string }[] = [];
  const loose: string[] = [];
  for (const text of details) {
    const match = /^([^:：]{1,40})[:：]\s*([\s\S]+)$/.exec(text.trim());
    if (!match) {
      loose.push(text);
      continue;
    }
    const [, label, value] = match;
    const key = label.trim().toLowerCase();
    if (LINE_KEYS.has(key)) line[key] = value.trim();
    else fields.push({ label: label.trim(), value: value.trim() });
  }
  return { line, fields, loose };
}

export function SceneIssue({ report, configured }: { report: Report; configured: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function dispatch() {
    setBusy(true);
    try {
      const response = await fetch("/api/content/issues/scene-" + report.id, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "dispatch", agent: "hana" }),
      });
      if (!response.ok) throw new Error((await response.json()).error);
      setError("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Dispatch failed");
    } finally {
      setBusy(false);
      router.refresh();
    }
  }

  const focus = parseFocusDetails(report.focusDetails);
  const device = [report.appVersion && `iOS app ${report.appVersion}`, report.osVersion && `OS ${report.osVersion}`]
    .filter(Boolean)
    .join(" · ");
  const hasLine = Boolean(focus.line.japanese || focus.line.english);

  return (
    <div className="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
      <div className="flex min-w-0 flex-col gap-6">
        <IssuePanel title="What the learner reported">
          {report.note ? (
            <blockquote className="border-l-2 border-border pl-3 text-sm whitespace-pre-wrap">“{report.note}”</blockquote>
          ) : (
            <p className="text-sm text-muted-foreground">No note from the learner.</p>
          )}
          {hasLine || report.focusTitle ? (
            <div className="flex flex-col gap-1 rounded-md bg-muted/40 px-3 py-2">
              <span className="text-xs text-muted-foreground">
                {[report.focusTitle, focus.line.speaker].filter(Boolean).join(" · ") || "Reported line"}
              </span>
              {focus.line.japanese ? (
                <span className="text-base" lang="ja">
                  {report.pickedWord && focus.line.japanese.includes(report.pickedWord)
                    ? focus.line.japanese.split(report.pickedWord).flatMap((part, i) =>
                        i === 0
                          ? [part]
                          : [
                              <span key={i} className="rounded bg-amber-200/70 px-0.5 font-medium dark:bg-amber-500/30">
                                {report.pickedWord}
                              </span>,
                              part,
                            ]
                      )
                    : focus.line.japanese}
                </span>
              ) : null}
              {focus.line.english ? <span className="text-sm text-muted-foreground">{focus.line.english}</span> : null}
            </div>
          ) : null}
          {focus.loose.map((text, i) => (
            <p key={i} className="text-sm text-muted-foreground">
              {text}
            </p>
          ))}
        </IssuePanel>

        <IssuePanel title="Where it happened">
          <dl className="grid grid-cols-[9rem_minmax(0,1fr)] gap-x-4 gap-y-2">
            {report.page ? <Field label="Page">{report.page}</Field> : null}
            {report.sessionMode ? <Field label="Mode">{report.sessionMode}</Field> : null}
            {report.quizQuestionNumber != null ? <Field label="Quiz question">{report.quizQuestionNumber}</Field> : null}
            {focus.fields
              .filter((field) => !(report.sessionMode && field.label.toLowerCase() === "session" && field.value === report.sessionMode))
              .map((field, i) => (
                <Field key={i} label={field.label}>
                  {field.value}
                </Field>
              ))}
            {report.pickedWord ? (
              <Field label="Picked word">
                <span lang="ja">{report.pickedWord}</span>
              </Field>
            ) : null}
            {report.playbackSeconds != null ? (
              <Field label="Playback position">
                <span className="tabular-nums">{report.playbackSeconds.toFixed(2)} s</span>
              </Field>
            ) : null}
            {device ? <Field label="Device">{device}</Field> : null}
          </dl>
        </IssuePanel>

        {report.publishedVariantId || report.reportedContentHash ? (
          <IssuePanel title="Reported version">
            <dl className="grid grid-cols-[9rem_minmax(0,1fr)] gap-x-4 gap-y-2">
              {report.publishedVariantId ? (
                <Field label="Voice take">
                  <code className="text-xs text-muted-foreground">{report.publishedVariantId}</code>
                </Field>
              ) : null}
              {report.reportedContentHash ? (
                <Field label="Content revision">
                  <code className="text-xs break-all text-muted-foreground">{report.reportedContentHash}</code>
                </Field>
              ) : null}
            </dl>
          </IssuePanel>
        ) : null}

        <IssuePanel
          title={
            <>
              Attempts{" "}
              {report.attempts.length > 0 ? (
                <span className="font-normal text-muted-foreground tabular-nums">{report.attempts.length}</span>
              ) : null}
            </>
          }
        >
          {report.attempts.length === 0 ? (
            <p className="text-sm text-muted-foreground">No agent has worked on this issue yet.</p>
          ) : (
            report.attempts.map((attempt) => {
              const [firstLine, ...rest] = (attempt.summary ?? "").split("\n");
              return (
                <article
                  key={attempt.id}
                  className="flex flex-col gap-1.5 rounded-md border border-border/60 bg-muted/30 p-2 text-sm"
                >
                  <div className="flex flex-wrap items-center gap-2">
                    <BotIcon className="size-4 text-muted-foreground" />
                    <span className="font-medium capitalize">{attempt.agent}</span>
                    <Badge variant={STATUS_VARIANT[attempt.status]}>
                      {attempt.status === "done" && attempt.outcome ? OUTCOME_LABELS[attempt.outcome] : attempt.status}
                    </Badge>
                    <LocalTime
                      iso={attempt.finishedAt ?? attempt.startedAt ?? attempt.createdAt}
                      className="ml-auto text-xs text-muted-foreground tabular-nums"
                    />
                  </div>
                  {firstLine ? <p>{firstLine}</p> : null}
                  {rest.join("\n").trim() ? (
                    <p className="text-xs whitespace-pre-wrap text-muted-foreground">{rest.join("\n").trim()}</p>
                  ) : null}
                  {attempt.status === "dispatched" ? (
                    <p className="text-xs text-muted-foreground">Waiting for the agent to pick it up.</p>
                  ) : null}
                  {attempt.revision ? (
                    <code className="text-xs break-all text-muted-foreground">Revision {attempt.revision}</code>
                  ) : null}
                </article>
              );
            })
          )}
        </IssuePanel>
      </div>

      <aside className="flex flex-col gap-4 lg:sticky lg:top-20">
        <IssuePanel title="Actions">
          {report.status === "open" ? (
            configured ? (
              <Button disabled={busy || Boolean(report.activeAttempt)} onClick={dispatch}>
                {busy ? <Loader2Icon className="animate-spin" /> : <SendIcon />}
                Send to Hana
              </Button>
            ) : (
              <p className="text-sm text-muted-foreground">
                Hana isn’t set up.{" "}
                <Link href="/settings/agents" className="text-foreground underline-offset-2 hover:underline">
                  Configure agents
                </Link>
              </p>
            )
          ) : (
            <p className="text-sm text-muted-foreground">This issue is closed.</p>
          )}
          {report.activeAttempt ? (
            <p className="text-xs text-muted-foreground">An attempt is in progress.</p>
          ) : null}
          {error ? (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          ) : null}
          <a
            href={`/api/content/issues/scene-${report.id}?published=1`}
            target="_blank"
            rel="noreferrer"
            className={buttonVariants({ variant: "ghost", size: "sm", className: "justify-start" })}
          >
            <ExternalLinkIcon />
            Inspect learner-visible scene
          </a>
        </IssuePanel>
        {report.activeAttempt ? (
          <RecoverIssueAttempt
            issueId={"scene-" + report.id}
            attemptId={report.activeAttempt}
            onChange={() => router.refresh()}
          />
        ) : null}
      </aside>
    </div>
  );
}
