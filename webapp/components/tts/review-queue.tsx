"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ttsApi, type ReviewQueueResult } from "@/lib/tts/client";
import type { TokenSyncFlag } from "@/lib/dialogue/types";
import { cn } from "@/lib/utils";

const FLAG_LABEL: Record<TokenSyncFlag["code"], string> = {
  "stamp-in-silence": "stamp in silence",
  "script-mismatch": "script mismatch",
  "reading-fallback": "reading fallback",
  "no-gap": "no gap",
};

function minutes(from?: string, to?: string): string | null {
  if (!from || !to) return null;
  const m = (new Date(to).getTime() - new Date(from).getTime()) / 60000;
  return m >= 0 ? `${m < 10 ? m.toFixed(1) : Math.round(m)} min` : null;
}

function fmt(n: number | null, unit = ""): string {
  return n == null ? "—" : `${n < 10 ? n.toFixed(1) : Math.round(n)}${unit}`;
}

function TimingSummary({ timing }: { timing: ReviewQueueResult["timing"] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Open-to-publish timing</CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-xs text-muted-foreground">
            <tr>
              <th className="py-1 pr-4 font-medium">Source</th>
              <th className="py-1 pr-4 font-medium">Published takes</th>
              <th className="py-1 pr-4 font-medium">Median open → publish</th>
              <th className="py-1 pr-4 font-medium">Lines untouched</th>
              <th className="py-1 pr-4 font-medium">Takes with a &gt;200 ms fix</th>
            </tr>
          </thead>
          <tbody>
            {timing.bySource.map((row) => (
              <tr key={row.source} className="border-t border-border/60">
                <td className="py-1.5 pr-4 font-medium">
                  {row.source === "auto" ? "auto / reviewed" : "hand-stamped"}
                </td>
                <td className="py-1.5 pr-4 tabular-nums">{row.published}</td>
                <td className="py-1.5 pr-4 tabular-nums">
                  {fmt(row.medianOpenToPublishMinutes, " min")}
                  {row.withOpenTiming < row.published && (
                    <span className="ml-1 text-xs text-muted-foreground">
                      ({row.withOpenTiming} timed)
                    </span>
                  )}
                </td>
                <td className="py-1.5 pr-4 tabular-nums">{fmt(row.linesUntouchedPct, "%")}</td>
                <td className="py-1.5 pr-4 tabular-nums">{fmt(row.correctionsOver200msPct, "%")}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="mt-2 text-xs text-muted-foreground">
          Clock starts the first time a take is opened in Token timing and stops at publish.
          v1 bar: ≥ 80% of lines untouched, ≤ 4 min per scene.
          {timing.since ? ` Measuring since ${new Date(timing.since).toLocaleDateString()}.` : " No published takes measured yet."}
        </p>
      </CardContent>
    </Card>
  );
}

function FlaggedLine({ line }: { line: ReviewQueueResult["takes"][number]["flaggedLines"][number] }) {
  return (
    <div className="flex flex-wrap items-center gap-x-1 gap-y-1 text-sm leading-relaxed">
      <span className="mr-1 font-mono text-[10px] text-muted-foreground">L{line.lineIndex + 1}</span>
      {line.lineCodes.map((code) => (
        <span
          key={code}
          className="rounded border border-amber-500/50 px-1 text-[10px] font-medium text-amber-700 dark:text-amber-300"
        >
          {FLAG_LABEL[code]}
        </span>
      ))}
      {line.tokens.map((token, i) => (
        <span
          key={`${i}-${token.text}`}
          title={token.codes.map((c) => FLAG_LABEL[c]).join("; ") || undefined}
          className={cn(
            "rounded px-0.5",
            token.codes.length > 0 && "border border-amber-500/70 bg-amber-500/15"
          )}
        >
          {token.text}
        </span>
      ))}
    </div>
  );
}

export function ReviewQueue() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["tts-review-queue"],
    queryFn: () => ttsApi.reviewQueue(),
    refetchInterval: 30_000,
  });

  if (isLoading) {
    return (
      <div className="flex flex-col gap-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }
  if (isError || !data) {
    return (
      <p className="text-sm text-destructive">
        {error instanceof Error ? error.message : "Could not load the review queue."}
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold">Review queue</h1>
        <p className="text-sm text-muted-foreground">
          Takes stamped by the aligner that nobody has marked reviewed, most flags first.
          Open one, listen through, fix flagged words, then Mark reviewed.
        </p>
      </div>
      <TimingSummary timing={data.timing} />
      {data.takes.length === 0 && (
        <p className="text-sm text-muted-foreground">Nothing waiting for review.</p>
      )}
      <div className="flex flex-col gap-3">
        {data.takes.map((take) => {
          const href =
            take.collectionId && take.slug
              ? `/content/dialogues/${take.collectionId}/${take.slug}?tab=audio&take=${take.variantId}`
              : `/tts/${take.projectId}?take=${take.variantId}`;
          const opened = take.timing?.openedAt;
          return (
            <Card key={take.variantId}>
              <CardHeader>
                <CardTitle className="flex flex-wrap items-center gap-2 text-base">
                  <Link href={href} className="underline-offset-4 hover:underline">
                    {take.title}
                  </Link>
                  {take.collectionId && (
                    <span className="text-xs font-normal text-muted-foreground">{take.collectionId}</span>
                  )}
                  <Badge
                    variant="outline"
                    className={cn(
                      take.flagCount > 0
                        ? "border-amber-500/50 text-amber-600 dark:text-amber-400"
                        : "border-emerald-500/50 text-emerald-600 dark:text-emerald-400"
                    )}
                  >
                    {take.flagCount === 0 ? "no flags" : `${take.flagCount} flagged`}
                  </Badge>
                  {take.isPublishedTake && <Badge variant="secondary">published</Badge>}
                  {take.isSelectedTake && !take.isPublishedTake && (
                    <Badge variant="secondary">selected</Badge>
                  )}
                  <span className="ml-auto text-xs font-normal text-muted-foreground">
                    {take.lineCount} lines · {take.tokenCount} tokens · {take.voice} ·{" "}
                    {new Date(take.createdAt).toLocaleString()}
                    {opened ? ` · opened ${new Date(opened).toLocaleString()}` : " · not opened yet"}
                    {take.timing?.publishedAt && minutes(opened, take.timing.publishedAt)
                      ? ` · ${minutes(opened, take.timing.publishedAt)} to publish`
                      : ""}
                  </span>
                </CardTitle>
              </CardHeader>
              {take.flaggedLines.length > 0 && (
                <CardContent className="flex flex-col gap-1.5">
                  <div className="flex flex-wrap gap-1 text-xs text-muted-foreground">
                    {Object.entries(take.flagsByCode).map(([code, n]) => (
                      <span key={code}>
                        {FLAG_LABEL[code as TokenSyncFlag["code"]]} ×{n}
                      </span>
                    ))}
                  </div>
                  {take.flaggedLines.map((line) => (
                    <FlaggedLine key={line.lineIndex} line={line} />
                  ))}
                </CardContent>
              )}
            </Card>
          );
        })}
      </div>
    </div>
  );
}
