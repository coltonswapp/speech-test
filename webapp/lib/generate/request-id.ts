/** Keep one UUID for retries of the same payload; allocate a new one when the payload changes. */
export function retainStableRequestId(
  previous: { payloadKey: string; requestId: string } | null,
  payloadKey: string,
  allocate: () => string = () => crypto.randomUUID(),
): { payloadKey: string; requestId: string } {
  if (previous && previous.payloadKey === payloadKey && previous.requestId) {
    return previous;
  }
  return { payloadKey, requestId: allocate() };
}
