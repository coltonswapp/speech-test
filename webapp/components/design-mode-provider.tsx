"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useSyncExternalStore,
} from "react";

const STORAGE_KEY = "design-mode";
type DesignMode = "classic" | "new";

const listeners = new Set<() => void>();

function emit() {
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  const onStorage = (event: StorageEvent) => {
    if (event.key === STORAGE_KEY || event.key === null) listener();
  };
  window.addEventListener("storage", onStorage);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", onStorage);
  };
}

function getSnapshot(): DesignMode {
  try {
    return localStorage.getItem(STORAGE_KEY) === "new" ? "new" : "classic";
  } catch {
    return "classic";
  }
}

function getServerSnapshot(): DesignMode {
  return "classic";
}

const DesignModeContext = createContext<{
  mode: DesignMode;
  setMode: (mode: DesignMode) => void;
} | null>(null);

export const DESIGN_MODE_INLINE_SCRIPT = `(function(){try{if(localStorage.getItem("${STORAGE_KEY}")==="new")document.documentElement.setAttribute("data-design","new")}catch(e){}})()`;

export function DesignModeProvider({ children }: { children: React.ReactNode }) {
  const mode = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);

  useEffect(() => {
    document.documentElement.setAttribute("data-design", mode);
  }, [mode]);

  const setMode = useCallback((next: DesignMode) => {
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      // localStorage unavailable (private mode, etc.) — still emit for this session
    }
    document.documentElement.setAttribute("data-design", next);
    emit();
  }, []);

  return (
    <DesignModeContext.Provider value={{ mode, setMode }}>
      {children}
    </DesignModeContext.Provider>
  );
}

export function useDesignMode() {
  const ctx = useContext(DesignModeContext);
  if (!ctx) {
    throw new Error("useDesignMode must be used within a DesignModeProvider");
  }
  return ctx;
}
