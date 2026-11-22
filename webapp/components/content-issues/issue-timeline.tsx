import { issueTimelineEvents } from "@/lib/content-issues/attempt-state";
import { LocalTime } from "./local-time";

/** One muted line: Reported · Agent finished · Resolved / Won’t fix / Duplicate. */
export function IssueTimeline({
  createdAt,
  agentFinishedAt,
  resolvedAt,
  status,
  className = "text-xs text-muted-foreground",
}: {
  createdAt?: string | null;
  agentFinishedAt?: string | null;
  resolvedAt?: string | null;
  status?: string | null;
  className?: string;
}) {
  const events = issueTimelineEvents({ createdAt, agentFinishedAt, resolvedAt, status });
  if (events.length === 0) return null;
  return (
    <p className={className}>
      {events.map((event, index) => (
        <span key={event.label}>
          {index > 0 ? " · " : null}
          {event.label} <LocalTime iso={event.at} className="tabular-nums" />
        </span>
      ))}
    </p>
  );
}
