import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { listClipFeedback } from "@/lib/clip-feedback/admin";
import { AttemptError, claimAttempt, finishAttempt, recoverClipAttempt, withAttempts } from "@/lib/clip-agent/store";
import { attemptErrorResponse, studioRequester } from "@/lib/clip-agent/route-helpers";
import { CLIP_AGENT_OUTCOMES } from "@/lib/clip-agent/schema";
import { finishScene, publishedScene, recoverSceneAttempt, sceneDetail, startScene } from "@/lib/content-issues/scenes";
import { parseIssueId, type IssueSubject } from "@/lib/content-issues/subjects";

type Context = { params: Promise<{ id: string }> };
const attemptId = z.string().regex(/^[a-zA-Z0-9_-]{1,128}$/);
const actionSchema = z.discriminatedUnion("action", [
  z.object({
    action: z.literal("claim"), agent: z.string().trim().min(1).max(40),
    attemptId: attemptId.optional(), takeOver: z.boolean().optional(), runUrl: z.string().url().optional(),
  }),
  z.object({ action: z.literal("dispatch"), agent: z.literal("hana") }),
  z.object({ action: z.literal("recover"), attemptId, reason: z.string().trim().min(1).max(500) }),
  z.object({
    action: z.literal("finish"), attemptId, outcome: z.enum(CLIP_AGENT_OUTCOMES),
    summary: z.string().trim().min(1).max(4000), revision: z.string().max(128).optional(),
  }),
]);
type Action = z.output<typeof actionSchema>;

async function clipDetail(id: string) {
  const [report] = await withAttempts(await listClipFeedback({ id, status: "issues" }));
  if (!report) throw new AttemptError("Issue not found", 404);
  const { userId: _userId, ...detail } = report;
  void _userId;
  return detail;
}

const handlers: Record<IssueSubject, {
  get: (id: string, published: boolean) => Promise<unknown>;
  act: (id: string, action: Action, requester: string) => Promise<unknown>;
}> = {
  clip: {
    get: clipDetail,
    async act(id, body, requester) {
      if (body.action === "dispatch") throw new AttemptError("Use clip dispatch", 400);
      if (body.action === "recover") return recoverClipAttempt(id, body.attemptId, requester, body.reason);
      if (body.action === "claim") {
        if (body.takeOver && !body.attemptId) throw new AttemptError("Takeover requires the current attempt ID", 400);
        return claimAttempt({
          feedbackId: id, agent: body.agent, claimedBy: requester,
          runUrl: body.runUrl ?? null, takeOver: body.takeOver ?? false, expectedAttempt: body.attemptId,
        });
      }
      return finishAttempt({ ...body, feedbackId: id });
    },
  },
  scene: {
    get: (id, published) => published ? publishedScene(id) : sceneDetail(id),
    act(id, body, requester) {
      if (body.action === "finish") {
        return finishScene(id, body.attemptId, body.outcome, body.summary, body.revision);
      }
      if (body.action === "recover") return recoverSceneAttempt(id, body.attemptId, requester, body.reason);
      if (body.action === "claim" && body.takeOver) throw new AttemptError("Recover the scene attempt before claiming again", 400);
      return startScene(id, body.action === "dispatch", body.agent, requester,
        body.action === "claim" ? body.attemptId : undefined);
    },
  },
};

async function requireIssue(context: Context) {
  const issue = parseIssueId((await context.params).id);
  if (!issue) throw new AttemptError("Unknown issue", 404);
  return { ...issue, handler: handlers[issue.subject] };
}

export async function GET(request: NextRequest, context: Context) {
  try {
    const { key, handler } = await requireIssue(context);
    return NextResponse.json(await handler.get(key, request.nextUrl.searchParams.get("published") === "1"));
  } catch (error) {
    return attemptErrorResponse(error, "get issue");
  }
}

export async function POST(request: NextRequest, context: Context) {
  try {
    const { key, handler } = await requireIssue(context);
    const parsed = actionSchema.safeParse(await request.json().catch(() => null));
    if (!parsed.success) throw new AttemptError("Invalid issue action", 400);
    return NextResponse.json(await handler.act(key, parsed.data, await studioRequester(request)));
  } catch (error) {
    return attemptErrorResponse(error, "issue action");
  }
}
