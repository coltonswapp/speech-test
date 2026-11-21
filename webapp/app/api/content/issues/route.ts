import { issueQuery, listIssues } from "@/lib/content-issues/queue";
export async function GET(request: Request) {
  const q = issueQuery.safeParse(Object.fromEntries(new URL(request.url).searchParams));
  if (!q.success) return Response.json({error:"Invalid queue filters"}, {status:400});
  return Response.json(await listIssues(q.data));
}
