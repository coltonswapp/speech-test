// Server routes return either a plain `{ error: string }` or a Zod
// `.flatten()` shape (`{ error: { formErrors, fieldErrors } }`). Field-level
// errors (e.g. an invalid slug) land in `fieldErrors`, not `formErrors` — a
// naive `formErrors.join(", ")` silently produces an empty message for those.
export function formatApiError(body: unknown, status: number): string {
  const error = (body as { error?: unknown } | null)?.error;
  if (typeof error === "string") return error;

  const flattened = error as
    | { formErrors?: string[]; fieldErrors?: Record<string, string[]> }
    | undefined;
  const messages = [
    ...(flattened?.formErrors ?? []),
    ...Object.values(flattened?.fieldErrors ?? {}).flat(),
  ];
  return messages.length > 0
    ? messages.join(", ")
    : `Request failed: ${status}`;
}
