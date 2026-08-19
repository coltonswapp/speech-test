"use client";

import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { useDesignMode } from "@/components/design-mode-provider";

export function NewDesignToggle() {
  const { mode, setMode } = useDesignMode();

  return (
    <div className="flex items-center gap-2">
      <Label htmlFor="new-design-toggle" className="text-sm text-muted-foreground">
        New Design
      </Label>
      <Switch
        id="new-design-toggle"
        checked={mode === "new"}
        onCheckedChange={(checked) => setMode(checked ? "new" : "classic")}
      />
    </div>
  );
}
