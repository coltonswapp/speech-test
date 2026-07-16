// Dialogue JSON import for TTS tracks (shizen collection format).
// parses a dialogue collection (e.g. shizen/Resources/Dialogue/train-station.json)
// into one importable script per scenario, mapping arbitrary speaker names to
// speaker1/speaker2 (Gemini's multi-speaker synthesis supports exactly two).

export type ImportedDialogueLine = {
  speaker: "speaker1" | "speaker2";
  text: string;
};

export type ImportedScript = {
  title: string | null;
  sourceId: string | null;
  lines: ImportedDialogueLine[];
  speaker1Name: string | null;
  speaker2Name: string | null;
};

export type ImportedCollection = {
  id: string | null;
  title: string | null;
  scripts: ImportedScript[];
};

export class SpeakerAssigner {
  private names: string[] = [];
  private overflow: string[] = [];

  speakerFor(rawName: string): "speaker1" | "speaker2" {
    const name = rawName.trim();
    const existingIndex = this.names.findIndex(
      (n) => n.toLowerCase() === name.toLowerCase()
    );
    if (existingIndex >= 0) {
      return existingIndex % 2 === 0 ? "speaker1" : "speaker2";
    }
    this.names.push(name);
    if (this.names.length > 2) this.overflow.push(name);
    return (this.names.length - 1) % 2 === 0 ? "speaker1" : "speaker2";
  }

  nameFor(speaker: "speaker1" | "speaker2"): string | null {
    const index = speaker === "speaker1" ? 0 : 1;
    return this.names[index] ?? null;
  }
}

type JsonValue = { [key: string]: unknown } | unknown[] | string | number | boolean | null;

function scriptFromLineDicts(
  lineDicts: unknown[],
  title: string | null,
  sourceId: string | null
): ImportedScript | null {
  const assigner = new SpeakerAssigner();
  const lines: ImportedDialogueLine[] = [];

  for (const raw of lineDicts) {
    if (typeof raw !== "object" || raw === null) return null;
    const dict = raw as Record<string, unknown>;
    const japanese = typeof dict.japanese === "string" ? dict.japanese.trim() : "";
    const speakerName = typeof dict.speaker === "string" ? dict.speaker.trim() : "";
    if (!japanese || !speakerName) return null;
    lines.push({ speaker: assigner.speakerFor(speakerName), text: japanese });
  }

  if (lines.length === 0) return null;

  return {
    title,
    sourceId,
    lines,
    speaker1Name: assigner.nameFor("speaker1"),
    speaker2Name: assigner.nameFor("speaker2"),
  };
}

function scenarios(
  node: JsonValue,
  inheritedTitle: string | null,
  inheritedId: string | null
): ImportedScript[] {
  if (Array.isArray(node)) {
    const asScript = scriptFromLineDicts(node, inheritedTitle, inheritedId);
    if (asScript) return [asScript];
    return node.flatMap((item) =>
      scenarios(item as JsonValue, inheritedTitle, inheritedId)
    );
  }

  if (typeof node === "object" && node !== null) {
    const dict = node as Record<string, unknown>;
    const title =
      (typeof dict.menuTitle === "string" && dict.menuTitle) ||
      (typeof dict.title === "string" && dict.title) ||
      inheritedTitle;
    const sourceId = (typeof dict.id === "string" && dict.id) || inheritedId;

    // shizen format: {"scenario": {"lines": [...]}} rather than a bare "lines" array.
    const scenarioObj = dict.scenario;
    if (
      typeof scenarioObj === "object" &&
      scenarioObj !== null &&
      Array.isArray((scenarioObj as Record<string, unknown>).lines)
    ) {
      const script = scriptFromLineDicts(
        (scenarioObj as Record<string, unknown>).lines as unknown[],
        title,
        sourceId
      );
      if (script) return [script];
    }

    if (Array.isArray(dict.lines)) {
      const script = scriptFromLineDicts(dict.lines, title, sourceId);
      if (script) return [script];
    }

    const results: ImportedScript[] = [];
    if (dict.scenarios !== undefined) {
      results.push(
        ...scenarios(dict.scenarios as JsonValue, title, sourceId)
      );
    }
    for (const key of Object.keys(dict).sort()) {
      if (key === "scenarios") continue;
      results.push(...scenarios(dict[key] as JsonValue, title, sourceId));
    }
    return results;
  }

  return [];
}

export function parseDialogueCollection(raw: string): ImportedCollection {
  const trimmed = raw.trim();
  if (!trimmed) return { id: null, title: null, scripts: [] };

  let json: JsonValue;
  try {
    json = JSON.parse(trimmed);
  } catch {
    return { id: null, title: null, scripts: [] };
  }

  const found = scenarios(json, null, null);
  const root =
    typeof json === "object" && !Array.isArray(json) && json !== null
      ? (json as Record<string, unknown>)
      : {};

  return {
    id: typeof root.id === "string" ? root.id : null,
    title: typeof root.title === "string" ? root.title : null,
    scripts: found,
  };
}
