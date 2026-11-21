import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeftIcon, ExternalLinkIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { parseIssueId } from "@/lib/content-issues/subjects";
import { ClipIssueDetail } from "@/components/experiments/clips/clip-feedback";
import { SceneIssue } from "@/components/content-issues/scene-issue";
import { LocalTime } from "@/components/content-issues/local-time";
import { agentSettings } from "@/lib/content-issues/agents";
import { sceneDetail } from "@/lib/content-issues/scenes";
import { issueReasonLabel, issueStatusLabel, ISSUE_SUBJECT_LABELS } from "@/lib/content-issues/labels";
import { AttemptError } from "@/lib/clip-agent/store";
import { listClipFeedback } from "@/lib/clip-feedback/admin";

export const dynamic = "force-dynamic";

function Header({
  eyebrow,
  title,
  status,
  reasons,
  createdAt,
  action,
}: {
  eyebrow: string;
  title: React.ReactNode;
  status: string | null;
  reasons: string[];
  createdAt: string | null;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-2">
      <Link
        href="/content/issues"
        className="inline-flex w-fit items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
      >
        <ChevronLeftIcon className="size-3" /> Content Issues
      </Link>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex min-w-0 flex-col gap-1.5">
          <span className="text-xs font-medium tracking-wide text-muted-foreground uppercase">{eyebrow}</span>
          <h1 className="text-xl font-semibold tracking-tight break-words">{title}</h1>
          <div className="flex flex-wrap items-center gap-2">
            {status ? (
              <Badge variant={status === "open" ? "destructive" : "secondary"}>{issueStatusLabel(status)}</Badge>
            ) : null}
            {reasons.map((reason) => (
              <Badge key={reason} variant="outline">
                {reason}
              </Badge>
            ))}
            <span className="text-xs text-muted-foreground">
              Reported <LocalTime iso={createdAt} className="tabular-nums" />
            </span>
          </div>
        </div>
        {action}
      </div>
    </div>
  );
}

export default async function DetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const issue = parseIssueId(id);
  if (!issue) notFound();
  const { subject: kind, key } = issue;

  if (kind === "clip") {
    const [report] = await listClipFeedback({ id: key, status: "issues" });
    if (!report) notFound();
    const start = Math.floor(report.videoStartSec + (report.line?.startSec ?? 0));
    return (
      <div className="flex flex-col gap-6">
        <Header
          eyebrow={`${ISSUE_SUBJECT_LABELS.clip} report`}
          title={
            <Link href={`/experiments/clips/${encodeURIComponent(report.clipId)}`} className="hover:underline">
              {report.clipTitle ?? report.clipId}
            </Link>
          }
          status={report.status}
          reasons={report.reason ? [issueReasonLabel("clip", report.reason)] : []}
          createdAt={report.createdAt}
          action={
            <Link
              href={`/experiments/clips/${encodeURIComponent(report.clipId)}`}
              className={buttonVariants({ size: "sm", variant: "outline" })}
            >
              Open clip editor
            </Link>
          }
        />
        <div className="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_24rem]">
          <div className="flex min-w-0 flex-col gap-4">
            <ClipIssueDetail id={key} />
          </div>
          {report.videoId ? (
            <aside className="flex flex-col gap-2 lg:sticky lg:top-20">
              <div className="overflow-hidden rounded-xl border border-border/60 bg-muted">
                <iframe
                  title="Reported clip"
                  className="aspect-video w-full"
                  allowFullScreen
                  src={`https://www.youtube-nocookie.com/embed/${encodeURIComponent(report.videoId)}?start=${start}`}
                />
              </div>
              <a
                href={`https://www.youtube.com/watch?v=${encodeURIComponent(report.videoId)}&t=${start}s`}
                target="_blank"
                rel="noreferrer"
                className="inline-flex w-fit items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
              >
                Starts at the reported line · Open on YouTube <ExternalLinkIcon className="size-3" />
              </a>
            </aside>
          ) : null}
        </div>
      </div>
    );
  }

  const report = await sceneDetail(key).catch((e) => {
    if (e instanceof AttemptError && e.status === 404) notFound();
    throw e;
  });
  const sceneHref = `/content/dialogues/${encodeURIComponent(report.collectionId)}/${encodeURIComponent(report.scenarioId)}`;
  return (
    <div className="flex flex-col gap-6">
      <Header
        eyebrow={`${ISSUE_SUBJECT_LABELS.scene} report`}
        title={
          <Link href={sceneHref} className="hover:underline">
            <span className="text-muted-foreground">{report.collectionId} / </span>
            {report.scenarioId}
          </Link>
        }
        status={report.status}
        reasons={report.categories.map((category) => issueReasonLabel("scene", category))}
        createdAt={report.createdAt}
        action={
          <Link
            href={sceneHref}
            className={buttonVariants({ size: "sm", variant: "outline" })}
          >
            Open scene editor
          </Link>
        }
      />
      <SceneIssue report={report} configured={(await agentSettings()).hana} />
    </div>
  );
}
