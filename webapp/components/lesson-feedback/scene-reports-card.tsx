"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { lessonReportsApi } from "@/lib/lesson-reports/client";
import {
  LESSON_REPORT_CATEGORIES,
  lessonReportCategoryLabels,
  lessonReportStatusLabels,
  type LessonReportEntry,
  type LessonReportStatus,
} from "@/lib/lesson-reports/types";

function formatWhen(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function ReportRow({
  entry,
  currentVariantId,
  pending,
  onSetStatus,
}: {
  entry: LessonReportEntry;
  currentVariantId: string | null;
  pending: boolean;
  onSetStatus: (status: LessonReportStatus) => void;
}) {
  const olderTake =
    currentVariantId != null &&
    entry.publishedVariantId != null &&
    entry.publishedVariantId !== currentVariantId;
  const meta = [
    entry.page,
    entry.sessionMode,
    entry.appVersion && `iOS app ${entry.appVersion}`,
    entry.osVersion && `OS ${entry.osVersion}`,
  ].filter(Boolean);

  return (
    <li className="flex flex-col gap-2 rounded-md border border-border/60 px-4 py-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs text-muted-foreground">
          {formatWhen(entry.createdAt)}
        </span>
        {entry.categories.map((category) => (
          <Badge key={category} variant="secondary">
            {lessonReportCategoryLabels[category]}
          </Badge>
        ))}
        {olderTake && <Badge variant="outline">Older take</Badge>}
        {entry.status !== "open" && (
          <Badge variant="outline">{lessonReportStatusLabels[entry.status]}</Badge>
        )}
      </div>

      {entry.note && <p className="text-sm whitespace-pre-wrap">{entry.note}</p>}

      {(entry.focusTitle || entry.focusDetails.length > 0) && (
        <div className="rounded-sm bg-muted/40 px-3 py-2 text-xs text-muted-foreground">
          {entry.focusTitle && (
            <p className="font-medium text-foreground">{entry.focusTitle}</p>
          )}
          {entry.focusDetails.map((line, index) => (
            <p key={index}>{line}</p>
          ))}
        </div>
      )}

      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs text-muted-foreground">{meta.join(" · ")}</span>
        <div className="flex gap-1">
          {entry.status === "open" ? (
            <>
              <Button
                size="xs"
                variant="outline"
                disabled={pending}
                onClick={() => onSetStatus("resolved")}
              >
                Resolve
              </Button>
              <Button
                size="xs"
                variant="ghost"
                disabled={pending}
                onClick={() => onSetStatus("wontfix")}
              >
                Won&apos;t fix
              </Button>
            </>
          ) : (
            <Button
              size="xs"
              variant="ghost"
              disabled={pending}
              onClick={() => onSetStatus("open")}
            >
              Reopen
            </Button>
          )}
        </div>
      </div>
    </li>
  );
}

export function SceneReportsCard({
  collectionId,
  scenarioSlug,
  currentVariantId,
}: {
  collectionId: string;
  scenarioSlug: string;
  currentVariantId: string | null;
}) {
  const [showAll, setShowAll] = useState(false);
  const queryClient = useQueryClient();
  const queryKey = ["lesson-reports", collectionId, scenarioSlug];

  const query = useQuery({
    queryKey,
    queryFn: () => lessonReportsApi.getScene(collectionId, scenarioSlug),
    staleTime: 60 * 1000,
  });

  const statusMutation = useMutation({
    mutationFn: ({ id, status }: { id: string; status: LessonReportStatus }) =>
      lessonReportsApi.setStatus(id, status),
    onSuccess: () => queryClient.invalidateQueries({ queryKey }),
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Failed to update report"),
  });

  const scene = query.data?.scene;
  const stats = scene?.stats;
  const reports = (scene?.recent ?? []).filter(
    (entry) => showAll || entry.status === "open",
  );

  return (
    <Card className="max-w-3xl">
      <CardHeader>
        <CardTitle className="text-base font-medium">Reported issues</CardTitle>
        <CardDescription>
          Problems learners flagged from the lesson menu in iOS.
          {stats && stats.count > 0
            ? ` ${stats.open} open of ${stats.count} total.`
            : null}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {query.isLoading && <Skeleton className="h-24 w-full" />}

        {query.isError && (
          <p className="text-sm text-destructive">
            {query.error instanceof Error
              ? query.error.message
              : "Failed to load reports"}
          </p>
        )}

        {query.data && !query.data.configured && (
          <p className="text-sm text-muted-foreground">
            {query.data.configError ?? "Firestore credentials not configured."}
          </p>
        )}

        {stats && stats.count === 0 && (
          <p className="text-sm text-muted-foreground">
            No reports for this scene.
          </p>
        )}

        {stats && stats.count > 0 && (
          <>
            <div className="flex flex-wrap gap-2">
              {LESSON_REPORT_CATEGORIES.filter(
                (category) => stats.categories[category] > 0,
              ).map((category) => (
                <Badge key={category} variant="outline">
                  {lessonReportCategoryLabels[category]} ·{" "}
                  {stats.categories[category]}
                </Badge>
              ))}
            </div>

            <div className="flex items-center justify-between">
              <h3 className="text-sm font-medium">
                {showAll ? "Recent reports" : "Open reports"}
              </h3>
              <label className="flex items-center gap-2 text-xs text-muted-foreground">
                Show resolved
                <Switch
                  checked={showAll}
                  onCheckedChange={(checked) => setShowAll(checked)}
                />
              </label>
            </div>

            {scene.recentError ? (
              <p className="text-xs text-muted-foreground">
                Could not load reports: {scene.recentError}
              </p>
            ) : reports.length === 0 ? (
              <p className="text-xs text-muted-foreground">
                {showAll
                  ? "No recent report documents (they expire after the retention window)."
                  : "Nothing open."}
              </p>
            ) : (
              <ul className="flex flex-col gap-2">
                {reports.map((entry) => (
                  <ReportRow
                    key={entry.id}
                    entry={entry}
                    currentVariantId={currentVariantId}
                    pending={
                      statusMutation.isPending &&
                      statusMutation.variables?.id === entry.id
                    }
                    onSetStatus={(status) =>
                      statusMutation.mutate({ id: entry.id, status })
                    }
                  />
                ))}
              </ul>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
