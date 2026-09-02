// Maps a scenario's rich dialogue lines (arbitrary speaker names) onto the
// two-voice conversation shape Gemini TTS synthesizes. Pure and client-safe —
// the Audio tab uses it to label voice pickers, the variants route to build
// the synthesis input, so both sides agree on the speaker1/speaker2 mapping.

import { isSpokenLine, type DialogueLine } from "@/lib/dialogue/types";
import { SpeakerAssigner } from "@/lib/tts/dialogue-import";

export type ConversationLine = {
  speaker: "speaker1" | "speaker2";
  text: string;
};

export type ScenarioConversation = {
  lines: ConversationLine[];
  speaker1Name: string | null;
  speaker2Name: string | null;
  /** Distinct speaker names in order of appearance; >2 means extras alternate voices. */
  speakerNames: string[];
};

export function scenarioLinesToConversation(
  lines: DialogueLine[]
): ScenarioConversation {
  const assigner = new SpeakerAssigner();
  const conversationLines: ConversationLine[] = [];
  const speakerNames: string[] = [];

  for (const line of lines) {
    // Stage / ト書き rows are not spoken: skip TTS and line-switch beats.
    if (!isSpokenLine(line)) continue;
    const speakerName = line.speaker.trim();
    const japanese = line.japanese.trim();
    if (!speakerName || !japanese) continue;
    if (!speakerNames.some((n) => n.toLowerCase() === speakerName.toLowerCase())) {
      speakerNames.push(speakerName);
    }
    conversationLines.push({
      speaker: assigner.speakerFor(speakerName),
      text: japanese,
    });
  }

  return {
    lines: conversationLines,
    speaker1Name: assigner.nameFor("speaker1"),
    speaker2Name: assigner.nameFor("speaker2"),
    speakerNames,
  };
}
