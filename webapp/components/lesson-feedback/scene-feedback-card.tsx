"use client";

import { useQuery } from "@tanstack/react-query";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { lessonFeedbackApi } from "@/lib/lesson-feedback/client";
import {
  LESSON_FEEDBACK_DIMENSIONS,
  lessonFeedbackDimensionLabels,
  type DimensionStats,
  type LessonFeedbackEntry,
} from "@/lib/lesson-feedback/types";
import { cn } from "@/lib/utils";

export function formatAverage(value: number | null | undefined): string {
  return value == null ? "—" : value.toFixed(1);
}

/** Red under 3, amber under 4, otherwise neutral. */
export function averageTone(value: number | null | undefined): string {
  if (value == null) return "text-muted-foreground";
  if (value < 3) return "text-destructive";
  if (value < 4) return "text-amber-600 dark:text-amber-400";
  return "text-foreground";
}

function Histogram({ stats }: { stats: DimensionStats }) {
  const max = Math.max(...stats.histogram, 1);
  return (
    <div className="flex h-10 items-end gap-1" aria-hidden>
      {stats.histogram.map((count, index) => (
        <div key={index} className="flex flex-1 flex-col items-center gap-0.5">
          <div
            className={cn(
              "w-full rounded-sm",
              index < 2 ? "bg-destructive/60" : "bg-primary/60",
            )}
            style={{ height: `${Math.max((count / max) * 28, count > 0 ? 3 : 1)}px` }}
            title={`${index + 1}: ${count}`}
          />
          <span className="text-[10px] leading-none text-muted-foreground">
            {index + 1}
          </span>
        </div>
      ))}
    </div>
  );
}

function RecentTable({
  entries,
  currentVariantId,
}: {
  entries: LessonFeedbackEntry[];
  currentVariantId: string | null;
}) {
  return (
    <div className="overflow-x-auto rounded-md border border-border/60">
      <table className="w-full min-w-[36rem] text-left text-sm">
        <thead className="border-b border-border/60 bg-muted/40 text-muted-foreground">
          <tr>
            <th className="px-3 py-2 font-medium">When</th>
            {LESSON_FEEDBACK_DIMENSIONS.map((dimension) => (
              <th key={dimension} className="px-3 py-2 text-right font-medium">
                {lessonFeedbackDimensionLabels[dimension]}
              </th>
            ))}
            <th className="px-3 py-2 text-right font-medium">Score</th>
            <th className="px-3 py-2 font-medium">Take</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => {
            const olderTake =
              currentVariantId != null &&
              entry.publishedVariantId != null &&
              entry.publishedVariantId !== currentVariantId;
            return (
              <tr key={entry.id} className="border-b border-border/40 last:border-0">
                <td className="px-3 py-2 text-muted-foreground">
                  {entry.createdAt
                    ? new Date(entry.createdAt).toLocaleString(undefined, {
                        month: "short",
                        day: "numeric",
                        hour: "numeric",
                        minute: "2-digit",
                      })
                    : "—"}
                </td>
                {LESSON_FEEDBACK_DIMENSIONS.map((dimension) => (
                  <td
                    key={dimension}
                    className={cn(
                      "px-3 py-2 text-right tabular-nums",
                      averageTone(entry.ratings[dimension]),
                    )}
                  >
                    {entry.ratings[dimension] ?? "—"}
                  </td>
                ))}
                <td className="px-3 py-2 text-right tabular-nums text-muted-foreground">
                  {entry.score
                    ? `${entry.score.correct}/${entry.score.total} · ${entry.score.stars}★`
                    : "—"}
                </td>
                <td className="px-3 py-2">
                  {olderTake ? (
                    <Badge variant="secondary">Older take</Badge>
                  ) : (
                    <span className="text-muted-foreground">Current</span>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export function SceneFeedbackCard({
  collectionId,
  scenarioSlug,
  currentVariantId,
}: {
  collectionId: string;
  scenarioSlug: string;
  currentVariantId: string | null;
}) {
  const query = useQuery({
    queryKey: ["lesson-feedback", collectionId, scenarioSlug],
    queryFn: () => lessonFeedbackApi.getScene(collectionId, scenarioSlug),
    staleTime: 60 * 1000,
  });

  const scene = query.data?.scene;
  const stats = scene?.stats;

  return (
    <Card className="max-w-3xl">
      <CardHeader>
        <CardTitle className="text-base font-medium">Learner feedback</CardTitle>
        <CardDescription>
          1–5 ratings from the iOS completion sheet, asked on a sample of
          finished attempts.
          {stats && stats.count > 0 ? ` ${stats.count} total.` : null}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {query.isLoading && <Skeleton className="h-24 w-full" />}

        {query.isError && (
          <p className="text-sm text-destructive">
            {query.error instanceof Error
              ? query.error.message
              : "Failed to load feedback"}
          </p>
        )}

        {query.data && !query.data.configured && (
          <p className="text-sm text-muted-foreground">
            {query.data.configError ?? "Firestore credentials not configured."}
          </p>
        )}

        {stats && stats.count === 0 && (
          <p className="text-sm text-muted-foreground">
            No ratings for this scene yet.
          </p>
        )}

        {stats && stats.count > 0 && (
          <>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {LESSON_FEEDBACK_DIMENSIONS.map((dimension) => {
                const dim = stats.dimensions[dimension];
                return (
                  <div
                    key={dimension}
                    className="flex flex-col gap-2 rounded-md border border-border/60 px-4 py-3"
                  >
                    <p className="text-xs text-muted-foreground">
                      {lessonFeedbackDimensionLabels[dimension]}
                    </p>
                    <p
                      className={cn(
                        "text-xl font-semibold tracking-tight tabular-nums",
                        averageTone(dim.average),
                      )}
                    >
                      {formatAverage(dim.average)}
                      <span className="ml-1 text-xs font-normal text-muted-foreground">
                        / 5 · {dim.n}
                      </span>
                    </p>
                    <Histogram stats={dim} />
                  </div>
                );
              })}
            </div>

            <div className="flex flex-col gap-2">
              <h3 className="text-sm font-medium">Recent ratings</h3>
              {scene.recentError ? (
                <p className="text-xs text-muted-foreground">
                  Could not load recent ratings: {scene.recentError}
                </p>
              ) : scene.recent.length === 0 ? (
                <p className="text-xs text-muted-foreground">
                  No recent rating documents (they expire after the retention
                  window).
                </p>
              ) : (
                <RecentTable
                  entries={scene.recent}
                  currentVariantId={currentVariantId}
                />
              )}
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
