"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  averageTone,
  formatAverage,
} from "@/components/lesson-feedback/scene-feedback-card";
import { lessonFeedbackApi } from "@/lib/lesson-feedback/client";
import {
  LESSON_FEEDBACK_DIMENSIONS,
  lessonFeedbackDimensionLabels,
} from "@/lib/lesson-feedback/types";
import { cn } from "@/lib/utils";

export function LowestRatedScenes() {
  const query = useQuery({
    queryKey: ["lesson-feedback-overview"],
    queryFn: () => lessonFeedbackApi.getOverview(25),
    staleTime: 60 * 1000,
  });

  const overview = query.data?.overview;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base font-medium">Lesson feedback</CardTitle>
        <CardDescription>
          All-time learner ratings per dialogue scene from{" "}
          <code className="text-xs">lessonFeedbackStats</code>, sorted by the
          scene&apos;s weakest dimension.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {query.isLoading && <Skeleton className="h-32 w-full" />}

        {query.isError && (
          <p className="text-sm text-destructive">
            {query.error instanceof Error
              ? query.error.message
              : "Failed to load lesson feedback"}
          </p>
        )}

        {query.data && !query.data.configured && (
          <p className="text-sm text-muted-foreground">
            {query.data.configError ?? "Firestore credentials not configured."}
          </p>
        )}

        {overview && (
          <>
            <div className="grid gap-3 sm:grid-cols-5">
              <div className="rounded-md border border-border/60 px-4 py-3">
                <p className="text-xs text-muted-foreground">Ratings</p>
                <p className="mt-1 text-xl font-semibold tracking-tight tabular-nums">
                  {overview.product.count}
                </p>
              </div>
              {LESSON_FEEDBACK_DIMENSIONS.map((dimension) => {
                const average = overview.product.dimensions[dimension].average;
                return (
                  <div
                    key={dimension}
                    className="rounded-md border border-border/60 px-4 py-3"
                  >
                    <p className="text-xs text-muted-foreground">
                      {lessonFeedbackDimensionLabels[dimension]}
                    </p>
                    <p
                      className={cn(
                        "mt-1 text-xl font-semibold tracking-tight tabular-nums",
                        averageTone(average),
                      )}
                    >
                      {formatAverage(average)}
                    </p>
                  </div>
                );
              })}
            </div>

            {overview.scenes.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No scenes have been rated yet.
              </p>
            ) : (
              <div className="overflow-x-auto rounded-md border border-border/60">
                <table className="w-full min-w-[40rem] text-left text-sm">
                  <thead className="border-b border-border/60 bg-muted/40 text-muted-foreground">
                    <tr>
                      <th className="px-3 py-2 font-medium">Scene</th>
                      <th className="px-3 py-2 text-right font-medium">Ratings</th>
                      {LESSON_FEEDBACK_DIMENSIONS.map((dimension) => (
                        <th
                          key={dimension}
                          className="px-3 py-2 text-right font-medium"
                        >
                          {lessonFeedbackDimensionLabels[dimension]}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {overview.scenes.map((scene) => {
                      const href =
                        scene.collectionId && scene.scenarioId
                          ? `/content/dialogues/${scene.collectionId}/${scene.scenarioId}`
                          : null;
                      return (
                        <tr
                          key={scene.sceneKey}
                          className="border-b border-border/40 last:border-0"
                        >
                          <td className="px-3 py-2 font-medium">
                            {href ? (
                              <Link href={href} className="hover:underline">
                                {scene.collectionId}/{scene.scenarioId}
                              </Link>
                            ) : (
                              scene.sceneKey
                            )}
                          </td>
                          <td className="px-3 py-2 text-right tabular-nums">
                            {scene.count}
                          </td>
                          {LESSON_FEEDBACK_DIMENSIONS.map((dimension) => {
                            const dim = scene.dimensions[dimension];
                            const isWeakest = scene.lowest?.dimension === dimension;
                            return (
                              <td
                                key={dimension}
                                className={cn(
                                  "px-3 py-2 text-right tabular-nums",
                                  averageTone(dim.average),
                                  isWeakest && "font-semibold",
                                )}
                                title={`${dim.n} rating${dim.n === 1 ? "" : "s"}`}
                              >
                                {formatAverage(dim.average)}
                              </td>
                            );
                          })}
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
