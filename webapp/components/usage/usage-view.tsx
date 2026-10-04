"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  Accordion,
  AccordionItem,
  AccordionPanel,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { LowestRatedScenes } from "@/components/lesson-feedback/lowest-rated-scenes";
import {
  usageApi,
  type FeedbackVotesApiResponse,
  type UsageApiResponse,
} from "@/lib/usage/client";
import type {
  FeedbackRating,
  FeedbackReason,
  FeedbackVoteDoc,
} from "@/lib/usage/parse-feedback-doc";
import type { UsageFeatureRow, UsagePeriodSnapshot } from "@/lib/usage/parse-period";
import {
  USAGE_PERIODS,
  type UsagePeriod,
} from "@/lib/usage/period-keys";

const periodLabels: Record<UsagePeriod, string> = {
  day: "Day",
  week: "Week",
  month: "Month",
};

type UsageSection = "aggregates" | "feedback";

type FeedbackRatingFilter = FeedbackRating | "all";

/** Built-in Studio operator quick-selects for per-user lookup. */
const USAGE_UID_BOOKMARKS = [
  { label: "Me", uid: "kYqKbEEc5FUmN2vLEWL3x9NRSVe2" },
] as const;

const REASON_LABELS: Record<FeedbackReason, string> = {
  wrong_meaning: "Wrong meaning",
  not_about_sentence: "Not about sentence",
  confusing: "Confusing",
};

function formatCount(value: number | null): string {
  if (value == null) return "—";
  return new Intl.NumberFormat("en-US").format(value);
}

function formatUsd(value: number | null): string {
  if (value == null) return "—";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 4,
  }).format(value);
}

function formatWhen(iso: string | null): string {
  if (!iso) return "—";
  const date = new Date(iso);
  if (!Number.isFinite(date.getTime())) return iso;
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "UTC",
  }).format(date) + " UTC";
}

function shortUid(uid: string): string {
  if (uid.length <= 12) return uid || "—";
  return `${uid.slice(0, 6)}…${uid.slice(-4)}`;
}

function PayloadJson({ value }: { value: unknown }) {
  let text: string;
  try {
    text = JSON.stringify(value, null, 2);
  } catch {
    text = String(value);
  }
  return (
    <pre className="max-h-64 overflow-auto rounded-md border border-border/60 bg-muted/30 p-3 font-mono text-xs whitespace-pre-wrap break-words">
      {text}
    </pre>
  );
}

function TotalsGrid({ snapshot }: { snapshot: UsagePeriodSnapshot }) {
  const unpriced = snapshot.unpricedCalls ?? 0;
  const showVotes = snapshot.up != null || snapshot.down != null;
  return (
    <div className="flex flex-col gap-2">
      <div className="grid gap-3 sm:grid-cols-3">
        <Metric label="Calls" value={formatCount(snapshot.calls)} />
        <Metric label="Tokens" value={formatCount(snapshot.tokens)} />
        <Metric
          label="Estimated USD"
          value={formatUsd(snapshot.estimatedUsd)}
        />
      </div>
      {showVotes && (
        <div className="grid gap-3 sm:grid-cols-2">
          <Metric label="Thumbs up" value={formatCount(snapshot.up)} />
          <Metric label="Thumbs down" value={formatCount(snapshot.down)} />
        </div>
      )}
      {unpriced > 0 && (
        <Badge variant="secondary" className="w-fit">
          {formatCount(unpriced)} unpriced call
          {unpriced === 1 ? "" : "s"}
        </Badge>
      )}
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-border/60 px-4 py-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-1 text-xl font-semibold tracking-tight tabular-nums">
        {value}
      </p>
    </div>
  );
}

function FeatureTable({ features }: { features: UsageFeatureRow[] }) {
  if (features.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        No feature breakdown on this period document.
      </p>
    );
  }

  return (
    <div className="overflow-x-auto rounded-md border border-border/60">
      <table className="w-full min-w-[36rem] text-left text-sm">
        <thead className="border-b border-border/60 bg-muted/40 text-muted-foreground">
          <tr>
            <th className="px-3 py-2 font-medium">Feature</th>
            <th className="px-3 py-2 font-medium text-right">Calls</th>
            <th className="px-3 py-2 font-medium text-right">Tokens</th>
            <th className="px-3 py-2 font-medium text-right">Est. USD</th>
            <th className="px-3 py-2 font-medium text-right">Up</th>
            <th className="px-3 py-2 font-medium text-right">Down</th>
          </tr>
        </thead>
        <tbody>
          {features.map((row) => (
            <tr
              key={row.feature}
              className="border-b border-border/40 last:border-0"
            >
              <td className="px-3 py-2 font-medium">{row.feature}</td>
              <td className="px-3 py-2 text-right tabular-nums">
                {formatCount(row.calls)}
              </td>
              <td className="px-3 py-2 text-right tabular-nums">
                {formatCount(row.tokens)}
              </td>
              <td className="px-3 py-2 text-right tabular-nums">
                {formatUsd(row.estimatedUsd)}
              </td>
              <td className="px-3 py-2 text-right tabular-nums">
                {formatCount(row.up)}
              </td>
              <td className="px-3 py-2 text-right tabular-nums">
                {formatCount(row.down)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function PeriodPanel({
  title,
  description,
  snapshot,
  emptyHint,
}: {
  title: string;
  description: string;
  snapshot: UsagePeriodSnapshot | null | undefined;
  emptyHint: string;
}) {
  if (!snapshot) return null;

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center gap-2">
          <CardTitle className="text-base font-medium">{title}</CardTitle>
          <Badge variant={snapshot.exists ? "default" : "secondary"}>
            {snapshot.exists ? "Loaded" : "Missing"}
          </Badge>
        </div>
        <CardDescription>
          {description}
          <span className="mt-1 block font-mono text-xs">
            {snapshot.path}
          </span>
          {snapshot.feedbackPath && (
            <span className="mt-0.5 block font-mono text-xs">
              {snapshot.feedbackPath}
            </span>
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {!snapshot.exists ? (
          <p className="text-sm text-muted-foreground">{emptyHint}</p>
        ) : (
          <>
            <TotalsGrid snapshot={snapshot} />
            <div className="flex flex-col gap-2">
              <h3 className="text-sm font-medium">Features by calls</h3>
              <FeatureTable features={snapshot.features} />
              {snapshot.rawKeys.length > 0 && snapshot.features.length === 0 && (
                <p className="text-xs text-muted-foreground">
                  Present keys: {snapshot.rawKeys.join(", ")}
                </p>
              )}
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}

function FeedbackVoteRow({ doc }: { doc: FeedbackVoteDoc }) {
  return (
    <AccordionItem value={doc.id}>
      <AccordionTrigger className="hover:no-underline">
        <div className="flex min-w-0 flex-1 flex-col gap-1.5 pr-2 sm:flex-row sm:items-center sm:gap-3">
          <div className="flex flex-wrap items-center gap-1.5">
            <Badge variant={doc.rating === "down" ? "destructive" : "default"}>
              {doc.rating}
            </Badge>
            <span className="font-medium">{doc.feature || "—"}</span>
            {doc.reason && (
              <Badge variant="secondary">
                {REASON_LABELS[doc.reason] ?? doc.reason}
              </Badge>
            )}
            {!doc.hasPayload && (
              <Badge variant="outline">vote only</Badge>
            )}
          </div>
          <div className="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-muted-foreground sm:ml-auto">
            <span>{formatWhen(doc.createdAt)}</span>
            <span className="font-mono" title={doc.uid}>
              {shortUid(doc.uid)}
            </span>
          </div>
        </div>
      </AccordionTrigger>
      <AccordionPanel>
        <div className="flex flex-col gap-3 text-sm">
          <dl className="grid gap-2 sm:grid-cols-2">
            <div>
              <dt className="text-xs text-muted-foreground">Request id</dt>
              <dd className="font-mono text-xs break-all">{doc.requestId}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Model</dt>
              <dd className="font-mono text-xs break-all">{doc.model || "—"}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Uid</dt>
              <dd className="font-mono text-xs break-all">{doc.uid || "—"}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Expires</dt>
              <dd className="text-xs">{formatWhen(doc.expiresAt)}</dd>
            </div>
          </dl>

          {doc.hasPayload ? (
            <div className="grid gap-3 lg:grid-cols-2">
              <div className="flex flex-col gap-1.5">
                <h4 className="text-xs font-medium text-muted-foreground">
                  Input
                </h4>
                <PayloadJson value={doc.input} />
              </div>
              <div className="flex flex-col gap-1.5">
                <h4 className="text-xs font-medium text-muted-foreground">
                  Result
                </h4>
                <PayloadJson value={doc.result} />
              </div>
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">
              No saved input/result on this vote (ups only store a payload about
              1 in 10 times).
            </p>
          )}
        </div>
      </AccordionPanel>
    </AccordionItem>
  );
}

function FeedbackVotesPanel() {
  const [rating, setRating] = useState<FeedbackRatingFilter>("all");

  const query = useQuery({
    queryKey: ["studio-usage-feedback", rating],
    queryFn: () =>
      usageApi.listFeedback({
        limit: 40,
        rating,
      }),
  });

  const data: FeedbackVotesApiResponse | undefined = query.data;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-lg font-medium tracking-tight">
            Gloss / LLM feedback
          </h2>
          <p className="text-sm text-muted-foreground">
            Read-only recent docs from{" "}
            <code className="text-xs">llmFeedback</code>. Downs include input
            and result; most ups are vote-only.
          </p>
        </div>
        <Tabs
          value={rating}
          onValueChange={(value) => {
            if (value === "all" || value === "up" || value === "down") {
              setRating(value);
            }
          }}
        >
          <TabsList>
            <TabsTrigger value="all" className="text-xs">
              All
            </TabsTrigger>
            <TabsTrigger value="down" className="text-xs">
              Downs
            </TabsTrigger>
            <TabsTrigger value="up" className="text-xs">
              Ups
            </TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      {query.isLoading && (
        <div className="flex flex-col gap-3">
          <Skeleton className="h-16 w-full" />
          <Skeleton className="h-16 w-full" />
          <Skeleton className="h-16 w-full" />
        </div>
      )}

      {query.isError && (
        <div className="rounded-md border border-destructive/40 bg-destructive/5 px-4 py-3 text-sm">
          {query.error instanceof Error
            ? query.error.message
            : "Failed to load feedback"}
        </div>
      )}

      {data && !data.configured && (
        <div className="rounded-md border border-border/60 bg-muted/30 px-4 py-3 text-sm">
          <p className="font-medium">Firestore credentials not configured</p>
          <p className="mt-1 text-muted-foreground">
            {data.configError ??
              "Set FIREBASE_PROJECT_ID and a service account (or ADC) on the Studio host."}
          </p>
        </div>
      )}

      {data && data.configured && (
        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-center gap-2">
              <CardTitle className="text-base font-medium">
                Recent votes
              </CardTitle>
              <Badge variant="secondary">{data.docs.length} shown</Badge>
            </div>
            <CardDescription>
              <span className="font-mono text-xs">
                {data.collection}
                {data.projectId ? ` · ${data.projectId}` : ""}
              </span>
            </CardDescription>
          </CardHeader>
          <CardContent>
            {data.docs.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No feedback documents in this window yet.
              </p>
            ) : (
              <Accordion className="rounded-md border border-border/60 px-3">
                {data.docs.map((doc) => (
                  <FeedbackVoteRow key={doc.id} doc={doc} />
                ))}
              </Accordion>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function AggregatesPanel() {
  const [period, setPeriod] = useState<UsagePeriod>("day");
  const [uidDraft, setUidDraft] = useState("");
  const [loadedUid, setLoadedUid] = useState<string | undefined>(undefined);

  const query = useQuery({
    queryKey: ["studio-usage", period, loadedUid ?? ""],
    queryFn: () => usageApi.get({ period, uid: loadedUid }),
  });

  const data: UsageApiResponse | undefined = query.data;

  const periodHint = useMemo(() => {
    if (!data) return null;
    return data.periodDocId;
  }, [data]);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-lg font-medium tracking-tight">Aggregates</h2>
          <p className="text-sm text-muted-foreground">
            Period rollups from{" "}
            <code className="text-xs">llmUsage</code> +{" "}
            <code className="text-xs">llmFeedbackStats</code>.
          </p>
        </div>
        <Tabs
          value={period}
          onValueChange={(value) => {
            if (value && (USAGE_PERIODS as readonly string[]).includes(value)) {
              setPeriod(value as UsagePeriod);
            }
          }}
        >
          <TabsList>
            {USAGE_PERIODS.map((key) => (
              <TabsTrigger key={key} value={key} className="text-xs">
                {periodLabels[key]}
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
      </div>

      {periodHint && (
        <p className="text-xs text-muted-foreground">
          Period document:{" "}
          <code className="font-mono">{periodHint}</code>
          {data?.projectId ? ` · project ${data.projectId}` : null}
        </p>
      )}

      {query.isLoading && (
        <div className="flex flex-col gap-3">
          <Skeleton className="h-28 w-full" />
          <Skeleton className="h-40 w-full" />
        </div>
      )}

      {query.isError && (
        <div className="rounded-md border border-destructive/40 bg-destructive/5 px-4 py-3 text-sm">
          {query.error instanceof Error
            ? query.error.message
            : "Failed to load usage"}
        </div>
      )}

      {data && !data.configured && (
        <div className="rounded-md border border-border/60 bg-muted/30 px-4 py-3 text-sm">
          <p className="font-medium">Firestore credentials not configured</p>
          <p className="mt-1 text-muted-foreground">
            {data.configError ??
              "Set FIREBASE_PROJECT_ID and a service account (or ADC) on the Studio host."}
          </p>
        </div>
      )}

      {data && (
        <>
          <PeriodPanel
            title="Product totals"
            description="Aggregates for all callers in this period."
            snapshot={data.product}
            emptyHint="No product period document for this window yet."
          />

          <Card>
            <CardHeader>
              <CardTitle className="text-base font-medium">
                Per-user lookup
              </CardTitle>
              <CardDescription>
                Studio-only. Paste a Firebase Auth uid to load that user&apos;s
                period doc. Learners cannot look up each other.
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
                <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                  <Label htmlFor="usage-uid">Firebase uid</Label>
                  <Input
                    id="usage-uid"
                    placeholder="e.g. abCdEf123…"
                    value={uidDraft}
                    onChange={(e) => setUidDraft(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        setLoadedUid(uidDraft.trim() || undefined);
                      }
                    }}
                    autoComplete="off"
                    spellCheck={false}
                  />
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  {USAGE_UID_BOOKMARKS.map((bookmark) => (
                    <Button
                      key={bookmark.uid}
                      type="button"
                      variant="outline"
                      size="sm"
                      disabled={query.isFetching}
                      onClick={() => {
                        setUidDraft(bookmark.uid);
                        setLoadedUid(bookmark.uid);
                      }}
                    >
                      {bookmark.label}
                    </Button>
                  ))}
                  <Button
                    type="button"
                    onClick={() => setLoadedUid(uidDraft.trim() || undefined)}
                    disabled={query.isFetching}
                  >
                    Load
                  </Button>
                  {loadedUid && (
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => {
                        setLoadedUid(undefined);
                        setUidDraft("");
                      }}
                    >
                      Clear
                    </Button>
                  )}
                </div>
              </div>

              {loadedUid && data.user ? (
                <div className="flex flex-col gap-3 rounded-md border border-border/60 p-4">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="text-sm font-medium">User {loadedUid}</p>
                    <Badge variant={data.user.exists ? "default" : "secondary"}>
                      {data.user.exists ? "Loaded" : "Missing"}
                    </Badge>
                  </div>
                  <p className="font-mono text-xs text-muted-foreground">
                    {data.user.path}
                  </p>
                  {data.user.feedbackPath && (
                    <p className="font-mono text-xs text-muted-foreground">
                      {data.user.feedbackPath}
                    </p>
                  )}
                  {!data.user.exists ? (
                    <p className="text-sm text-muted-foreground">
                      No period document for this uid and window.
                    </p>
                  ) : (
                    <>
                      <TotalsGrid snapshot={data.user} />
                      <div className="flex flex-col gap-2">
                        <h3 className="text-sm font-medium">
                          Features by calls
                        </h3>
                        <FeatureTable features={data.user.features} />
                        {data.user.rawKeys.length > 0 &&
                          data.user.features.length === 0 && (
                            <p className="text-xs text-muted-foreground">
                              Present keys: {data.user.rawKeys.join(", ")}
                            </p>
                          )}
                      </div>
                    </>
                  )}
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">
                  Enter a uid and press Load to fetch{" "}
                  <code className="text-xs">
                    llmUsage/{"{uid}"}/periods/{periodHint ?? "…"}
                  </code>
                  .
                </p>
              )}
            </CardContent>
          </Card>
        </>
      )}

      <LowestRatedScenes />
    </div>
  );
}

export function UsageView() {
  const [section, setSection] = useState<UsageSection>("aggregates");

  return (
    <div className="flex flex-1 flex-col gap-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Usage</h1>
          <p className="text-sm text-muted-foreground">
            Read-only LLM usage and feedback for Studio operators. Aggregates
            stay on the counts tab; open Feedback to read individual gloss
            votes.
          </p>
        </div>
        <Tabs
          value={section}
          onValueChange={(value) => {
            if (value === "aggregates" || value === "feedback") {
              setSection(value);
            }
          }}
        >
          <TabsList>
            <TabsTrigger value="aggregates" className="text-xs">
              Aggregates
            </TabsTrigger>
            <TabsTrigger value="feedback" className="text-xs">
              Feedback
            </TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      {section === "aggregates" ? <AggregatesPanel /> : <FeedbackVotesPanel />}
    </div>
  );
}
