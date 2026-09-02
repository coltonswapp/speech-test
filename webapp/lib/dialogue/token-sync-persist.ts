// Serializes token-sync PATCHes so Publish can wait for the latest stamps
// instead of racing a debounced save (or an unmount flush).

let pending: Promise<void> = Promise.resolve();

export function enqueueTokenSyncSave(work: () => Promise<void>): Promise<void> {
  pending = pending.catch(() => undefined).then(work);
  return pending;
}

export function flushPendingTokenSync(): Promise<void> {
  return pending;
}
