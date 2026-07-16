"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import type { GrammarPoint } from "@/lib/content/client";

export function RawJsonEditor({
  point,
  onApply,
}: {
  point: GrammarPoint;
  onApply: (point: GrammarPoint) => void;
}) {
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setText(JSON.stringify(point, null, 2));
    setError(null);
  }, [point]);

  function validate(): GrammarPoint | null {
    try {
      const parsed = JSON.parse(text);
      if (typeof parsed !== "object" || parsed === null) {
        setError("Must be a JSON object.");
        return null;
      }
      if (!parsed.id || !parsed.title) {
        setError("Missing required fields: id, title.");
        return null;
      }
      setError(null);
      return parsed as GrammarPoint;
    } catch (e) {
      setError(e instanceof Error ? e.message : "Invalid JSON.");
      return null;
    }
  }

  function redecode() {
    const parsed = validate();
    if (parsed) {
      onApply(parsed);
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <Textarea
        rows={24}
        value={text}
        onChange={(e) => setText(e.target.value)}
        className="font-mono text-xs"
        spellCheck={false}
      />
      {error && <p className="text-sm text-destructive">{error}</p>}
      <div className="flex gap-2">
        <Button variant="outline" size="sm" onClick={validate}>
          Validate
        </Button>
        <Button size="sm" onClick={redecode}>
          Redecode into editor
        </Button>
      </div>
    </div>
  );
}
