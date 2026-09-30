import { createHash } from "node:crypto";

type Severity = "INFO" | "WARNING" | "ERROR";

/** One JSON object per line; Cloud Run turns these into filterable `jsonPayload` fields. */
export function log(severity: Severity, message: string, fields: Record<string, unknown> = {}): void {
  const line = JSON.stringify({ severity, message, ...fields });
  if (severity === "ERROR") {
    console.error(line);
  } else {
    console.log(line);
  }
}

/** Stable short id so repeat calls from one user group together without logging the uid. */
export function userHash(uid: string): string {
  return createHash("sha256").update(uid).digest("hex").slice(0, 12);
}
