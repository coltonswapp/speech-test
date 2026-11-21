import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { clipFeedbackReasonLabels, clipFeedbackStatusLabels } from "@/lib/clip-feedback/schema";
import { issueQuery, listIssues } from "@/lib/content-issues/queue";
import { lessonReportCategoryLabels } from "@/lib/lesson-reports/types";

export const dynamic = "force-dynamic";

const subjects = [
  { value: "all", label: "All subjects" },
  { value: "clip", label: "Clips" },
  { value: "scene", label: "Scenes" },
] as const;

const statuses = [
  { value: "open", label: clipFeedbackStatusLabels.open },
  { value: "resolved", label: clipFeedbackStatusLabels.resolved },
  { value: "wontfix", label: clipFeedbackStatusLabels.wontfix },
  { value: "duplicate", label: "Duplicate" },
  { value: "all", label: "All statuses" },
] as const;

function queueHref(filters: { subject: string; status: string; cursor?: string }) {
  const params = new URLSearchParams({ subject: filters.subject, status: filters.status });
  if (filters.cursor) params.set("cursor", filters.cursor);
  return "/content/issues?" + params;
}

const formatDate = new Intl.DateTimeFormat("en", {
  year: "numeric", month: "short", day: "numeric", timeZone: "UTC",
});

export default async function IssuesPage({ searchParams }: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const filters = issueQuery.safeParse(await searchParams);
  const q = filters.success ? filters.data : issueQuery.parse({});
  const { issues, next, warning } = await listIssues(q);

  return (
    <div className="flex min-w-0 flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Content Issues</h1>
        <p className="text-sm text-muted-foreground">Learner reports on clips and lesson scenes.</p>
      </div>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <nav aria-label="Issue status" className="flex flex-wrap items-center gap-2">
          {statuses.map(({ value, label }) => (
            <Link key={value} href={queueHref({ subject: q.subject, status: value })}
              aria-current={q.status === value ? "true" : undefined}
              className={buttonVariants({ size: "sm", variant: q.status === value ? "default" : "outline" })}>
              {label}
            </Link>
          ))}
        </nav>
        <nav aria-label="Issue subject" className="flex flex-wrap items-center gap-2">
          {subjects.map(({ value, label }) => (
            <Link key={value} href={queueHref({ status: q.status, subject: value })}
              aria-current={q.subject === value ? "true" : undefined}
              className={buttonVariants({ size: "sm", variant: q.subject === value ? "secondary" : "outline" })}>
              {label}
            </Link>
          ))}
        </nav>
      </div>

      {warning && <p role="status" className="text-sm text-muted-foreground">{warning}</p>}
      {issues.length ? (
        <ul className="divide-y divide-border/60 rounded-xl border border-border/60">
          {issues.map(issue => {
            const labels: Record<string, string> = issue.subject === "clip"
              ? clipFeedbackReasonLabels : lessonReportCategoryLabels;
            return (
              <li key={issue.id} className="flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3">
                <div className="flex min-w-0 flex-1 basis-52 flex-col gap-1">
                  <Link href={"/content/issues/" + issue.id}
                    className="w-fit max-w-full wrap-anywhere text-sm font-medium underline-offset-2 hover:underline">
                    {issue.title}
                  </Link>
                  <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
                    <span>{issue.subject === "clip" ? "Clip" : "Scene"}</span>
                    {issue.createdAt && <time dateTime={issue.createdAt}>{formatDate.format(new Date(issue.createdAt))}</time>}
                    {issue.status && (
                      <Badge variant={issue.status === "open" ? "destructive" : "secondary"}>
                        {clipFeedbackStatusLabels[issue.status]}
                      </Badge>
                    )}
                    {issue.reasons.map(reason => <Badge key={reason} variant="outline">{labels[reason] ?? reason}</Badge>)}
                  </div>
                  {(issue.note || issue.location) && <p className="line-clamp-2 wrap-anywhere text-xs text-muted-foreground">{issue.note || issue.location}</p>}
                </div>
                {issue.editorHref && (
                  <Link href={issue.editorHref} className={buttonVariants({ size: "sm", variant: "outline" })}>
                    {issue.subject === "clip" ? "Open clip editor" : "Open scene editor"}
                  </Link>
                )}
              </li>
            );
          })}
        </ul>
      ) : (
        <p className="text-sm text-muted-foreground">No matching issues.</p>
      )}
      {next && (
        <Link href={queueHref(next)} className={buttonVariants({ size: "sm", variant: "outline", className: "self-start" })}>
          Older issues
        </Link>
      )}
    </div>
  );
}
