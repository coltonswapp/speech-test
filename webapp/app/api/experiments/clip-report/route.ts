import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { clipChecks, type ClipChecks } from "@/lib/experiments/clips/checks";
import { clipErrorResponse } from "@/lib/experiments/clips/route-helpers";
import { isValidClipId, listClipDrafts, readClipDraft } from "@/lib/experiments/clips/store";
import { runCost } from "@/lib/experiments/clips/usage-cost";
import type { ClipDraft } from "@/lib/experiments/clips/types";

/**
 * Quality and cost across clips, for agents (Studio MCP) and scripts: each
 * clip's warnings, feed rules and missing steps (lib/experiments/clips/checks.ts)
 * plus library totals. Reads every draft from R2, so it is a few seconds on a
 * big library.
 *
 * `?ids=a,b` limits it to those clips (unknown ids come back in `missing`).
 * `?since=2026-11-01` limits the cost totals to runs on or after that date.
 */
export async function GET(request: NextRequest) {
  try {
    const params = request.nextUrl.searchParams;
    const idsParam = params.get("ids");
    const since = params.get("since");
    const sinceMs = since ? Date.parse(since) : null;
    if (since && !Number.isFinite(sinceMs)) {
      return NextResponse.json({ error: "since must be a date (YYYY-MM-DD)." }, { status: 400 });
    }

    let drafts: ClipDraft[];
    const missing: string[] = [];
    if (idsParam) {
      const ids = [...new Set(idsParam.split(",").map((id) => id.trim()).filter(Boolean))];
      if (ids.length > 200) {
        return NextResponse.json({ error: "At most 200 ids." }, { status: 400 });
      }
      const loaded = await Promise.all(
        ids.map(async (id) => (isValidClipId(id) ? readClipDraft(id) : null))
      );
      drafts = [];
      loaded.forEach((draft, i) => (draft ? drafts.push(draft) : missing.push(ids[i]!)));
    } else {
      drafts = await listClipDrafts();
    }

    const clips: ClipChecks[] = drafts.map(clipChecks);
    return NextResponse.json(
      { clips, missing, totals: totals(drafts, clips, sinceMs) },
      { headers: { "Cache-Control": "private, no-store" } }
    );
  } catch (error) {
    return clipErrorResponse(error);
  }
}

function bump(record: Record<string, number>, key: string, by = 1) {
  record[key] = (record[key] ?? 0) + by;
}

function totals(drafts: ClipDraft[], clips: ClipChecks[], sinceMs: number | null) {
  const feed: Record<string, number> = {};
  const level: Record<string, number> = {};
  const missingStep: Record<string, number> = {};
  const feedOutReasons: Record<string, number> = {};
  const channels: Record<
    string,
    { clips: number; inFeed: number; levels: Record<string, number>; usd: number }
  > = {};
  const needsLook = {
    unreviewedFlaggedLines: [] as string[],
    readingFallback: [] as string[],
    weakTiming: [] as string[],
    basicSplit: [] as string[],
    missingEnglish: [] as string[],
    notAligned: [] as string[],
    noSpeech: [] as string[],
    unrated: [] as string[],
  };

  for (const c of clips) {
    if (c.deprecated) {
      bump(feed, "deprecated");
      continue;
    }
    bump(feed, c.feed.state);
    bump(level, c.jlptLevel ? `N${c.jlptLevel}` : "unrated");
    for (const step of c.missingSteps) bump(missingStep, step);
    if (c.feed.state === "out" && c.feed.reason) {
      // Group model reasons loosely: measured rules start with a fixed phrase.
      const key = c.feed.reason.startsWith("Too short")
        ? "too short"
        : c.feed.reason.startsWith("Too long")
          ? "too long"
          : c.feed.reason.startsWith("Not much said")
            ? "not much said"
            : "model judged unsuitable";
      bump(feedOutReasons, key);
    }
    const ch = c.channelName ?? "(no video info)";
    channels[ch] ??= { clips: 0, inFeed: 0, levels: {}, usd: 0 };
    channels[ch].clips++;
    if (c.feed.eligible) channels[ch].inFeed++;
    bump(channels[ch].levels, c.jlptLevel ? `N${c.jlptLevel}` : "unrated");
    channels[ch].usd += c.cost.usd;

    if (c.counts.unreviewedFlaggedLines > 0) needsLook.unreviewedFlaggedLines.push(c.id);
    if (c.counts.readingFallbackTokens > 0) needsLook.readingFallback.push(c.id);
    if (c.counts.weakLines > 0) needsLook.weakTiming.push(c.id);
    if (c.counts.basicSplitLines > 0) needsLook.basicSplit.push(c.id);
    if (c.counts.missingEnglish > 0 && c.counts.lines > 0) needsLook.missingEnglish.push(c.id);
    if (c.missingSteps.includes("align") && !c.noSpeech) needsLook.notAligned.push(c.id);
    if (c.noSpeech) needsLook.noSpeech.push(c.id);
    if (c.jlptLevel === null && !c.noSpeech) needsLook.unrated.push(c.id);
  }

  const cost = {
    usd: 0,
    floor: false,
    unpricedRuns: 0,
    byStep: {} as Record<string, number>,
    byModel: {} as Record<string, number>,
    byDay: {} as Record<string, number>,
    runs: 0,
  };
  for (const draft of drafts) {
    for (const run of draft.usage ?? []) {
      if (sinceMs !== null && Date.parse(run.at) < sinceMs) continue;
      cost.runs++;
      const c = runCost(run);
      if (c === null) {
        if (run.step !== "align") cost.unpricedRuns++;
        continue;
      }
      cost.usd += c.usd;
      cost.floor ||= c.floor;
      bump(cost.byStep, run.step, c.usd);
      bump(cost.byModel, run.model, c.usd);
      bump(cost.byDay, run.at.slice(0, 10), c.usd);
    }
  }

  return {
    clips: clips.length,
    feed,
    level,
    missingStep,
    feedOutReasons,
    channels,
    needsLook,
    cost: { ...cost, perClipUsd: clips.length ? cost.usd / clips.length : 0 },
  };
}
