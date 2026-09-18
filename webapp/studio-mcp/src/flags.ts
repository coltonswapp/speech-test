import { isSpokenLine, isStageLine, type DialogueLine } from "./client.ts";

const TOGAKI_RE = /[（(][^）)]+[）)]/g;
export const LONG_B_LINE_CHARS = 24;

export function uniqueSpeakers(lines: DialogueLine[]): string[] {
  const names: string[] = [];
  for (const line of lines) {
    if (!isSpokenLine(line)) continue;
    const name = (line.speaker ?? "").trim();
    if (!name) continue;
    if (!names.some((n) => n.toLowerCase() === name.toLowerCase())) {
      names.push(name);
    }
  }
  return names;
}

/** Learner B: Kaito if present, else the second speaker in appearance order. */
export function inferBSpeaker(lines: DialogueLine[]): string | null {
  const speakers = uniqueSpeakers(lines);
  const kaito = speakers.find((n) => n.toLowerCase() === "kaito");
  if (kaito) return kaito;
  if (speakers.length >= 2) return speakers[1];
  return speakers[0] ?? null;
}

export function extractTogaki(japanese: string): string[] {
  return japanese.match(TOGAKI_RE) ?? [];
}

export function japaneseLengthExcludingTogaki(japanese: string): number {
  const stripped = japanese.replace(TOGAKI_RE, "").replace(/\s+/g, "");
  return Array.from(stripped).length;
}

export function hasOpenerStage(lines: DialogueLine[]): boolean {
  for (const line of lines) {
    if (isSpokenLine(line)) return false;
    if (isStageLine(line)) return true;
  }
  return false;
}

export type LineFlags = {
  longB?: boolean;
  togaki: string[];
};

export type ScenarioFlags = {
  missingTogaki: boolean;
  longBLines: Array<{ index: number; speaker: string; length: number; japanese: string }>;
  bSpeaker: string | null;
};

export function analyzeScenario(lines: DialogueLine[]): {
  speakers: string[];
  bSpeaker: string | null;
  flags: ScenarioFlags;
  lineMeta: Array<{
    index: number;
    role: "A" | "B" | "stage" | "?";
    jpLength: number;
    togaki: string[];
    longB: boolean;
  }>;
} {
  const speakers = uniqueSpeakers(lines);
  const bSpeaker = inferBSpeaker(lines);
  const aSpeaker =
    speakers.find((n) => n.toLowerCase() !== (bSpeaker ?? "").toLowerCase()) ??
    speakers[0] ??
    null;

  const longBLines: ScenarioFlags["longBLines"] = [];
  const lineMeta = lines.map((line, index) => {
    if (isStageLine(line)) {
      return {
        index,
        role: "stage" as const,
        jpLength: 0,
        togaki: line.text.trim() ? [line.text] : [],
        longB: false,
      };
    }
    const togaki = extractTogaki(line.japanese ?? "");
    const jpLength = japaneseLengthExcludingTogaki(line.japanese ?? "");
    const name = (line.speaker ?? "").trim();
    const isB =
      !!bSpeaker && name.toLowerCase() === bSpeaker.toLowerCase();
    const isA =
      !!aSpeaker && name.toLowerCase() === aSpeaker.toLowerCase();
    const longB = isB && jpLength > LONG_B_LINE_CHARS;
    if (longB) {
      longBLines.push({
        index,
        speaker: name,
        length: jpLength,
        japanese: line.japanese,
      });
    }
    return {
      index,
      role: (isB ? "B" : isA ? "A" : "?") as "A" | "B" | "?",
      jpLength,
      togaki,
      longB,
    };
  });

  const spokenCount = lines.filter(isSpokenLine).length;

  return {
    speakers,
    bSpeaker,
    flags: {
      missingTogaki: spokenCount > 0 && !hasOpenerStage(lines),
      longBLines,
      bSpeaker,
    },
    lineMeta,
  };
}
