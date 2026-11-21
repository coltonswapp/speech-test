import Link from "next/link";
import { ChevronRightIcon, FilmIcon, InboxIcon, MessagesSquareIcon, TriangleAlertIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { LocalTime } from "@/components/content-issues/local-time";
import { issueSubjects, type IssueSubject } from "@/lib/content-issues/subjects";
import { issueQuery, listIssues } from "@/lib/content-issues/queue";
import { issueReasonLabel, issueStatusLabel, ISSUE_SUBJECT_LABELS } from "@/lib/content-issues/labels";
import { cn } from "@/lib/utils";

export const dynamic = "force-dynamic";

type Query = ReturnType<typeof issueQuery.parse>;

const SUBJECT_FILTERS: { value: Query["subject"]; label: string }[] = [
  { value: "all", label: "All" },
  ...issueSubjects.map((subject) => ({ value: subject, label: ISSUE_SUBJECT_LABELS[subject] + "s" })),
];

const STATUS_FILTERS: { value: Query["status"]; label: string }[] = [
  { value: "open", label: "Open" },
  { value: "resolved", label: "Resolved" },
  { value: "wontfix", label: "Won’t fix" },
  { value: "duplicate", label: "Duplicate" },
  { value: "all", label: "All" },
];

const SUBJECT_ICONS: Record<IssueSubject, typeof FilmIcon> = {
  clip: FilmIcon,
  scene: MessagesSquareIcon,
};

function href(params: Partial<Query>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null) search.set(key, String(value));
  }
  const query = search.toString();
  return query ? `/content/issues?${query}` : "/content/issues";
}

function FilterGroup<T extends string>({
  label,
  options,
  current,
  link,
}: {
  label: string;
  options: { value: T; label: string }[];
  current: T;
  link: (value: T) => string;
}) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="w-14 text-xs text-muted-foreground">{label}</span>
      {options.map((option) => (
        <Link
          key={option.value}
          href={link(option.value)}
          aria-current={option.value === current ? "true" : undefined}
          className={buttonVariants({ size: "sm", variant: option.value === current ? "default" : "outline" })}
        >
          {option.label}
        </Link>
      ))}
    </div>
  );
}

export default async function IssuesPage({ searchParams }: { searchParams: Promise<Record<string, string>> }) {
  const filters = issueQuery.safeParse(await searchParams);
  const q = filters.success ? filters.data : issueQuery.parse({});
  const { issues, next, warning } = await listIssues(q);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Content Issues</h1>
        <p className="text-sm text-muted-foreground">
          Problems learners reported from the app, on clips and dialogue scenes. Newest first.
        </p>
      </div>

      <div className="flex flex-col gap-2">
        <FilterGroup
          label="Subject"
          options={SUBJECT_FILTERS}
          current={q.subject}
          link={(subject) => href({ subject, status: q.status })}
        />
        <FilterGroup
          label="Status"
          options={STATUS_FILTERS}
          current={q.status}
          link={(status) => href({ subject: q.subject, status })}
        />
      </div>

      {warning ? (
        <p
          role="status"
          className="flex items-center gap-2 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-700 dark:text-amber-400"
        >
          <TriangleAlertIcon className="size-4 shrink-0" />
          {warning}
        </p>
      ) : null}

      {issues.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-xl border border-dashed border-border/60 px-4 py-12 text-center">
          <InboxIcon className="size-6 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            {q.cursor ? "No older issues." : "No issues match these filters."}
          </p>
        </div>
      ) : (
        <ul className="divide-y divide-border/60 overflow-hidden rounded-xl border border-border/60">
          {issues.map((issue) => {
            const Icon = SUBJECT_ICONS[issue.subject];
            const detail = issue.note || issue.location;
            return (
              <li key={issue.id}>
                <Link
                  href={`/content/issues/${issue.id}`}
                  className="group flex items-start gap-3 px-4 py-3 transition-colors hover:bg-muted/40"
                >
                  <span
                    className="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-md bg-muted text-muted-foreground"
                    title={ISSUE_SUBJECT_LABELS[issue.subject]}
                  >
                    <Icon className="size-4" />
                  </span>
                  <div className="flex min-w-0 flex-1 flex-col gap-1">
                    <div className="flex min-w-0 flex-wrap items-center gap-2">
                      <span className="truncate text-sm font-medium group-hover:underline">{issue.title}</span>
                      {issue.reasons.map((reason) => (
                        <Badge key={reason} variant="secondary">
                          {issueReasonLabel(issue.subject, reason)}
                        </Badge>
                      ))}
                    </div>
                    {detail ? (
                      <p
                        className={cn(
                          "line-clamp-2 text-sm",
                          issue.note ? "text-foreground/80" : "text-muted-foreground"
                        )}
                        lang={issue.note ? undefined : "ja"}
                      >
                        {issue.note ? `“${issue.note}”` : issue.location}
                      </p>
                    ) : null}
                    <span className="text-xs text-muted-foreground">{ISSUE_SUBJECT_LABELS[issue.subject]}</span>
                  </div>
                  <div className="flex shrink-0 flex-col items-end gap-1.5">
                    {issue.status ? (
                      <Badge variant={issue.status === "open" ? "destructive" : "secondary"}>
                        {issueStatusLabel(issue.status)}
                      </Badge>
                    ) : null}
                    <LocalTime iso={issue.createdAt} className="text-xs text-muted-foreground tabular-nums" />
                  </div>
                  <ChevronRightIcon className="mt-2 size-4 shrink-0 text-muted-foreground/60" />
                </Link>
              </li>
            );
          })}
        </ul>
      )}

      {next || q.cursor ? (
        <div className="flex items-center gap-2">
          {q.cursor ? (
            <Link href={href({ subject: q.subject, status: q.status })} className={buttonVariants({ size: "sm", variant: "ghost" })}>
              Newest
            </Link>
          ) : null}
          {next ? (
            <Link href={href(next)} className={buttonVariants({ size: "sm", variant: "outline" })}>
              Older issues
            </Link>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
