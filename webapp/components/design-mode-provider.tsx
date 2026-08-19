"use client";

import { createContext, useCallback, useContext, useEffect, useState } from "react";

const STORAGE_KEY = "design-mode";
type DesignMode = "classic" | "new";

const DesignModeContext = createContext<{
  mode: DesignMode;
  setMode: (mode: DesignMode) => void;
} | null>(null);

export const DESIGN_MODE_INLINE_SCRIPT = `(function(){try{if(localStorage.getItem("${STORAGE_KEY}")==="new")document.documentElement.setAttribute("data-design","new")}catch(e){}})()`;

function readStoredMode(): DesignMode {
  if (typeof window === "undefined") return "classic";
  return localStorage.getItem(STORAGE_KEY) === "new" ? "new" : "classic";
}

export function DesignModeProvider({ children }: { children: React.ReactNode }) {
  const [mode, setModeState] = useState<DesignMode>(readStoredMode);

  useEffect(() => {
    document.documentElement.setAttribute("data-design", mode);
  }, [mode]);

  const setMode = useCallback((next: DesignMode) => {
    setModeState(next);
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      // localStorage unavailable (private mode, etc.) — mode still applies for this session
    }
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
