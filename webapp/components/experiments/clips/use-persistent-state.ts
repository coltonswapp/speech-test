"use client";

import { useCallback, useMemo, useSyncExternalStore } from "react";

// useState backed by localStorage (JSON). The server render and hydration use
// `initial`; the stored value takes over after. Every hook on the same key
// stays in sync, in this tab and others. If storage is blocked, values still
// hold for the visit (kept in memory).

const memory = new Map<string, string>();
const listeners = new Set<() => void>();

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  window.addEventListener("storage", listener);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", listener);
  };
}

function readRaw(key: string): string | null {
  if (memory.has(key)) return memory.get(key)!;
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

export function usePersistentState<T>(key: string, initial: T): [T, (value: T) => void] {
  const raw = useSyncExternalStore(
    subscribe,
    () => readRaw(key),
    () => null
  );
  const value = useMemo(() => {
    if (raw === null) return initial;
    try {
      return JSON.parse(raw) as T;
    } catch {
      return initial;
    }
    // `initial` is a default; only a change of stored value matters.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [raw]);

  const set = useCallback(
    (next: T) => {
      const encoded = JSON.stringify(next);
      memory.set(key, encoded);
      try {
        window.localStorage.setItem(key, encoded);
      } catch {
        // Storage full or blocked: the in-memory value still applies.
      }
      listeners.forEach((listener) => listener());
    },
    [key]
  );

  return [value, set];
}
