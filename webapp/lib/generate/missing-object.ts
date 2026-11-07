/** True only for a missing R2/S3 object. Other errors must not be treated as success. */
export function isMissingObjectError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const e = error as {
    name?: string;
    Code?: string;
    code?: string;
    $metadata?: { httpStatusCode?: number };
  };
  if (e.name === "NoSuchKey" || e.name === "NotFound") return true;
  if (e.Code === "NoSuchKey" || e.code === "NoSuchKey") return true;
  if (e.$metadata?.httpStatusCode === 404) return true;
  return false;
}
