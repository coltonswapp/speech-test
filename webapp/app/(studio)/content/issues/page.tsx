import Link from "next/link";
import { issueSubjects } from "@/lib/content-issues/subjects";
import { issueQuery, listIssues } from "@/lib/content-issues/queue";

export const dynamic = "force-dynamic";
export default async function IssuesPage({searchParams}:{searchParams:Promise<Record<string,string>>}) {
  const filters = issueQuery.safeParse(await searchParams);
  const q = filters.success ? filters.data : issueQuery.parse({});
  const {issues,next,warning} = await listIssues(q);
  return <main className="mx-auto max-w-5xl space-y-5 p-6">
    <h1 className="text-2xl font-semibold">Content Issues</h1>
    <form className="flex flex-wrap items-center gap-3">
      <label>Subject <select className="rounded border p-1" name="subject" defaultValue={q.subject}>{["all", ...issueSubjects].map(s=><option key={s}>{s}</option>)}</select></label>
      <label>Status <select className="rounded border p-1" name="status" defaultValue={q.status}>{["open","resolved","wontfix","duplicate","all"].map(s=><option key={s}>{s}</option>)}</select></label>
      <button className="rounded border px-3 py-1">Apply</button>
    </form>
    {warning && <p role="status">{warning}</p>}
    <ul className="divide-y rounded border">{issues.map(i=><li key={i.id}><Link href={"/content/issues/"+i.id} className="block space-y-1 p-3 hover:bg-muted">
      <span className="text-xs text-muted-foreground">{i.subject} · {i.status} · {i.createdAt.slice(0,10)}</span>
      <p className="font-semibold">{i.title} · {i.reasons.join(", ")}</p>
      <p className="line-clamp-2 text-sm">{i.note || i.location}</p>
    </Link></li>)}</ul>
    {!issues.length && <p>No matching issues.</p>}
    {next && <Link className="underline" href={"?"+new URLSearchParams(Object.entries(next).map(([k,v])=>[k,String(v)]))}>Older issues</Link>}
  </main>;
}
