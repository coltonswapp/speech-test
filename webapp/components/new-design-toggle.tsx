"use client";

import { useSyncExternalStore } from "react";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { useDesignMode } from "@/components/design-mode-provider";

const noopSubscribe = () => () => {};

export function NewDesignToggle() {
  const { mode, setMode } = useDesignMode();
  // Hydrate as unchecked so SSR HTML matches; flip after mount.
  const mounted = useSyncExternalStore(
    noopSubscribe,
    () => true,
    () => false,
  );
  const checked = mounted && mode === "new";

  return (
    <div className="flex items-center gap-2">
      <Label htmlFor="new-design-toggle" className="text-sm text-muted-foreground">
        New Design
      </Label>
      <Switch
        id="new-design-toggle"
        checked={checked}
        onCheckedChange={(next) => setMode(next ? "new" : "classic")}
      />
    </div>
  );
}
