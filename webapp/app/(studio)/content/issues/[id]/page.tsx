import Link from "next/link";
import { notFound } from "next/navigation";
import { parseIssueId } from "@/lib/content-issues/subjects";
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
  if (kind === "clip") {
    const [report] = await listClipFeedback({id:key,status:"issues"});
    if (!report) notFound();
    detail = <>{report.videoId && <iframe title="Reported clip" className="aspect-video w-full rounded" allowFullScreen src={`https://www.youtube-nocookie.com/embed/${encodeURIComponent(report.videoId)}?start=${Math.floor(report.videoStartSec + (report.line?.startSec ?? 0))}`}/>}<ClipIssueDetail id={key}/></>;
  } else {
    const report = await sceneDetail(key).catch(e=>{if(e instanceof AttemptError && e.status === 404) notFound(); throw e});
    detail = <SceneIssue report={report} configured={(await agentSettings()).hana}/>;
  }
  return <main className="mx-auto max-w-3xl space-y-5 p-6"><Link className="underline" href="/content/issues">Content Issues</Link><h1 className="text-2xl font-semibold">{kind === "clip" ? "Clip" : "Scene"} report</h1>{detail}</main>;
}
