"use client";

import { AlertTriangle, CheckCircle2, Info, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { AuditIssue, AuditScenarioResult } from "@/lib/dialogue/types";
import { cn } from "@/lib/utils";

function severityIcon(severity: AuditIssue["severity"]) {
  switch (severity) {
    case "error":
      return AlertTriangle;
    case "warning":
      return AlertTriangle;
    default:
      return Info;
  }
}

function severityClass(severity: AuditIssue["severity"]) {
  switch (severity) {
    case "error":
      return "text-destructive";
    case "warning":
      return "text-amber-600 dark:text-amber-400";
    default:
      return "text-muted-foreground";
  }
}

export function ScenarioAuditPanel({
  result,
  isAuditing,
  onApply,
  onDismiss,
}: {
  result: AuditScenarioResult | null;
  isAuditing: boolean;
  onApply: () => void;
  onDismiss: () => void;
}) {
  if (isAuditing) {
    return (
      <div className="rounded-md border border-border/60 bg-muted/30 px-4 py-3 text-sm text-muted-foreground">
        Auditing content…
      </div>
    );
  }

  if (!result) return null;

  const hasProposed =
    result.proposed.lines !== undefined ||
    result.proposed.highlights !== undefined ||
    result.proposed.grammarPointIds !== undefined;

  const errors = result.issues.filter((i) => i.severity === "error");
  const warnings = result.issues.filter((i) => i.severity === "warning");
  const infos = result.issues.filter((i) => i.severity === "info");

  if (result.issues.length === 0) {
    return (
      <div className="flex items-start justify-between gap-3 rounded-md border border-emerald-500/30 bg-emerald-50/50 px-4 py-3 dark:bg-emerald-950/20">
        <div className="flex items-start gap-2">
          <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-emerald-600 dark:text-emerald-400" />
          <div>
            <p className="text-sm font-medium text-emerald-900 dark:text-emerald-100">
              No issues found
            </p>
            <p className="text-xs text-emerald-800/80 dark:text-emerald-200/80">
              Grammar patterns and line tags look consistent.
            </p>
          </div>
        </div>
        <Button variant="ghost" size="icon-sm" onClick={onDismiss} aria-label="Dismiss">
          <X className="size-4" />
        </Button>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3 rounded-md border border-border/60 bg-muted/20 p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-medium">Content audit</p>
          <p className="text-xs text-muted-foreground">
            {errors.length > 0 && `${errors.length} error${errors.length === 1 ? "" : "s"}`}
            {errors.length > 0 && (warnings.length > 0 || infos.length > 0) && ", "}
            {warnings.length > 0 &&
              `${warnings.length} warning${warnings.length === 1 ? "" : "s"}`}
            {warnings.length > 0 && infos.length > 0 && ", "}
            {infos.length > 0 &&
              `${infos.length} note${infos.length === 1 ? "" : "s"}`}
            {result.llmFailed && " (semantic check skipped)"}
          </p>
        </div>
        <Button variant="ghost" size="icon-sm" onClick={onDismiss} aria-label="Dismiss">
          <X className="size-4" />
        </Button>
      </div>

      <ul className="flex max-h-64 flex-col gap-2 overflow-y-auto text-sm">
        {result.issues.map((issue, index) => {
          const Icon = severityIcon(issue.severity);
          return (
            <li key={`${issue.code}-${index}`} className="flex items-start gap-2">
              <Icon
                className={cn("mt-0.5 size-3.5 shrink-0", severityClass(issue.severity))}
              />
              <span>{issue.message}</span>
            </li>
          );
        })}
      </ul>

      {hasProposed && (
        <div className="flex flex-wrap items-center gap-2 border-t border-border/50 pt-3">
          <Button size="sm" onClick={onApply}>
            Apply proposed fixes
          </Button>
          <p className="text-xs text-muted-foreground">
            Updates the draft only — Save to persist.
            {result.proposed.lines && " Lines"}
            {result.proposed.lines &&
              (result.proposed.highlights || result.proposed.grammarPointIds) &&
              " +"}
            {result.proposed.highlights && " Highlights"}
            {result.proposed.highlights && result.proposed.grammarPointIds && " +"}
            {result.proposed.grammarPointIds && " Scenario grammar"}
          </p>
        </div>
      )}
    </div>
  );
}
