import Link from "next/link";
import { ChevronLeftIcon } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { notFound } from "next/navigation";
import { clipEditorHref, parseIssueId, sceneEditorHref } from "@/lib/content-issues/subjects";
import { ClipIssueDetail } from "@/components/experiments/clips/clip-feedback";
import { SceneIssue } from "@/components/content-issues/scene-issue";
import { agentSettings } from "@/lib/content-issues/agents";
import { sceneDetail } from "@/lib/content-issues/scenes";
import { AttemptError } from "@/lib/clip-agent/store";
import { listClipFeedback } from "@/lib/clip-feedback/admin";

export const dynamic = "force-dynamic";
export default async function DetailPage({params}:{params:Promise<{id:string}>}) {
  const {id} = await params;
  const issue = parseIssueId(id);
  if (!issue) notFound();
  const { subject: kind, key } = issue;
  let detail;
  let parentHref: string | null = null;
  if (kind === "clip") {
    const [report] = await listClipFeedback({id:key,status:"issues"});
    if (!report) notFound();
    parentHref = clipEditorHref(report.clipId);
    detail = <>{report.videoId && <iframe title="Reported clip" className="aspect-video w-full rounded-xl border border-border/60" allowFullScreen src={`https://www.youtube-nocookie.com/embed/${encodeURIComponent(report.videoId)}?start=${Math.floor(report.videoStartSec + (report.line?.startSec ?? 0))}`}/>}<ClipIssueDetail id={key}/></>;
  } else {
    const report = await sceneDetail(key).catch(e=>{if(e instanceof AttemptError && e.status === 404) notFound(); throw e});
    parentHref = sceneEditorHref(report.collectionId, report.scenarioId);
    detail = <SceneIssue report={report} configured={(await agentSettings()).hana}/>;
  }
  return (
    <div className="flex w-full max-w-3xl flex-col gap-6">
      <div>
        <Link href="/content/issues"
          className="mb-1 inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground">
          <ChevronLeftIcon className="size-3" /> Content Issues
        </Link>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h1 className="text-xl font-semibold tracking-tight">{kind === "clip" ? "Clip" : "Scene"} report</h1>
          {parentHref && <Link href={parentHref} className={buttonVariants({ size: "sm", variant: "outline" })}>Open {kind === "clip" ? "clip" : "scene"} editor</Link>}
        </div>
      </div>
      {detail}
    </div>
  );
}
