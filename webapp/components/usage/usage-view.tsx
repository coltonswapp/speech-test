"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
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
import { usageApi, type UsageApiResponse } from "@/lib/usage/client";
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

/** Built-in Studio operator quick-selects for per-user lookup. */
const USAGE_UID_BOOKMARKS = [
  { label: "Me", uid: "kYqKbEEc5FUmN2vLEWL3x9NRSVe2" },
] as const;

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

function TotalsGrid({ snapshot }: { snapshot: UsagePeriodSnapshot }) {
  return (
    <div className="grid gap-3 sm:grid-cols-3">
      <Metric label="Calls" value={formatCount(snapshot.calls)} />
      <Metric label="Tokens" value={formatCount(snapshot.tokens)} />
      <Metric label="Estimated USD" value={formatUsd(snapshot.estimatedUsd)} />
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
      <table className="w-full min-w-[28rem] text-left text-sm">
        <thead className="border-b border-border/60 bg-muted/40 text-muted-foreground">
          <tr>
            <th className="px-3 py-2 font-medium">Feature</th>
            <th className="px-3 py-2 font-medium text-right">Calls</th>
            <th className="px-3 py-2 font-medium text-right">Tokens</th>
            <th className="px-3 py-2 font-medium text-right">Est. USD</th>
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

export function UsageView() {
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
    <div className="flex flex-1 flex-col gap-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Usage</h1>
          <p className="text-sm text-muted-foreground">
            Read-only Gemini / LLM aggregates from Firestore (
            <code className="text-xs">llmUsage</code>). Product totals and
            optional per-uid lookup for Studio operators.
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
            emptyHint="No product period document for this window yet. Empty is expected until the llm-gateway writers land."
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
    </div>
  );
}
