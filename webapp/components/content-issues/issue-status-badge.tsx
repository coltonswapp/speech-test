import { Badge } from "@/components/ui/badge";
import { issueStatusLabel } from "@/lib/content-issues/labels";

/** Open stays red unless an agent left the report for a person, or is still working. */
export function IssueStatusBadge({
  status,
  needsReview = false,
  agentWorking = false,
}: {
  status: string | null;
  needsReview?: boolean;
  agentWorking?: boolean;
}) {
  if (!status) return null;
  if (status === "open" && needsReview) {
    return <Badge className="bg-amber-500 text-white">Needs review</Badge>;
  }
  if (status === "open" && agentWorking) {
    return <Badge variant="outline">Agent working</Badge>;
  }
  return (
    <Badge variant={status === "open" ? "destructive" : "secondary"}>{issueStatusLabel(status)}</Badge>
  );
}
