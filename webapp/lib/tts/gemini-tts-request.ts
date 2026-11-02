// Pure Gemini TTS request building (no server-only imports) so it can be unit
// tested and reused by standalone scripts. Port of
// TTSCore/Sources/TTSCore/GeminiTTS.swift, extended for the 3.8 TTS schema.
//
// 3.8+ (`usesSpeechMetadata`): `text` is read verbatim, so each turn is its own
// part with `speechMetadata.speaker` (required for multi-speaker), sustained
// delivery goes in `speechMetadata.style`, and one-off vocal sounds are inline
// angle-bracket tags (<laugh>, <sigh>). Speaker prefixes, the style cue and
// square-bracket tags in `text` would be spoken aloud or ignored.
// 3.1 and earlier: one "Name: [tag] text" transcript block (unchanged).

import { usesSpeechMetadata } from "../gemini/models";

export type ConversationSpeaker = "speaker1" | "speaker2";

export type ConversationDialogueLine = {
  speaker: ConversationSpeaker;
  /** Clean Japanese dialogue (no audio tags). */
  text: string;
  /** Optional Studio delivery tag(s), e.g. "[softly]" — TTS prompt only. */
  delivery?: string;
};

const DEFAULT_SPEAKER_LABEL: Record<ConversationSpeaker, string> = {
  speaker1: "Speaker 1",
  speaker2: "Speaker 2",
};

/**
 * Labels used in the Gemini transcript + multiSpeakerVoiceConfig.speaker fields.
 * Prefer character names (Kaito/Mika) — generic "Speaker 1/2" is more prone to the
 * known multi-speaker voice-swap quirk on the first turn.
 */
export function resolveSpeakerLabels(params: {
  speaker1Name?: string | null;
  speaker2Name?: string | null;
}): Record<ConversationSpeaker, string> {
  const raw1 = params.speaker1Name?.trim() || "";
  const raw2 = params.speaker2Name?.trim() || "";
  if (raw1 && raw2 && raw1.toLowerCase() !== raw2.toLowerCase()) {
    return { speaker1: raw1, speaker2: raw2 };
  }
  return { ...DEFAULT_SPEAKER_LABEL };
}

function spokenTextForPrompt(line: ConversationDialogueLine): string {
  const text = line.text.trim();
  const delivery = line.delivery?.trim();
  return delivery ? `${delivery} ${text}` : text;
}

/** Legacy (3.1 and earlier) single-block transcript with "Name: text" turns. */
export function buildLegacyTranscript(
  lines: ConversationDialogueLine[],
  labels: Record<ConversationSpeaker, string>
): string {
  const body = lines
    .map((line) => `${labels[line.speaker]}: ${spokenTextForPrompt(line)}`)
    .join("\n");
  // Brief style cue helps Gemini keep voices attached to the right speaker.
  const cue = `TTS dialogue. ${labels.speaker1} uses voice A; ${labels.speaker2} uses voice B. Keep each speaker's voice consistent for every line.\n\n`;
  return `${cue}## Transcript:\n${body}`;
}

// Studio tag (lowercased, inside the brackets) → 3.8 inline vocal tag.
// Everything else is sustained delivery and goes to `style`.
const VOCAL_EVENT_TAGS: Record<string, string> = {
  laugh: "<laugh>",
  laughs: "<laugh>",
  laughing: "<laugh>",
  "light laugh": "<chuckle>",
  "soft laugh": "<chuckle>",
  chuckle: "<chuckle>",
  chuckles: "<chuckle>",
  giggle: "<giggle>",
  giggles: "<giggle>",
  giggling: "<giggle>",
  sigh: "<sigh>",
  sighs: "<sigh>",
  gasp: "<gasp>",
  gasps: "<gasp>",
  cough: "<cough>",
  coughs: "<cough>",
  breath: "<breath>",
  "deep breath": "<heavy breath>",
  exhales: "<exhales>",
  yawn: "<yawn>",
  yawns: "<yawn>",
  phew: "<phew>",
  tsk: "<tsk>",
  pause: "<short pause>",
  "short pause": "<short pause>",
  "long pause": "<long pause>",
};

export type DeliveryForSpeech = {
  /** Sustained turn-level delivery for `speechMetadata.style`. */
  style?: string;
  /** Inline angle-bracket vocal events to prefix the turn's text. */
  events: string[];
};

/**
 * Splits a Studio delivery string ("[warmly]", "[laughs]", "[softly] [sighs]",
 * or "<laugh>") into a 3.8 `style` and inline vocal events.
 */
export function deliveryForSpeech(delivery: string | undefined): DeliveryForSpeech {
  const raw = delivery?.trim();
  if (!raw) return { events: [] };
  const bracketed = [...raw.matchAll(/[[<]([^\]>]+)[\]>]/g)].map((m) => m[1].trim());
  const tags = bracketed.length > 0 ? bracketed : [raw];
  const styles: string[] = [];
  const events: string[] = [];
  for (const tag of tags) {
    if (!tag) continue;
    const event = VOCAL_EVENT_TAGS[tag.toLowerCase()];
    if (event) events.push(event);
    else styles.push(tag);
  }
  return { ...(styles.length > 0 ? { style: styles.join(", ") } : {}), events };
}

/** 3.8+ request parts: one per turn, verbatim text plus `speechMetadata`. */
export function buildSpeechMetadataParts(
  lines: ConversationDialogueLine[],
  labels: Record<ConversationSpeaker, string>
) {
  return lines.map((line) => {
    const { style, events } = deliveryForSpeech(line.delivery);
    const text = line.text.trim();
    return {
      text: events.length > 0 ? `${events.join(" ")} ${text}` : text,
      speechMetadata: {
        speaker: labels[line.speaker],
        ...(style ? { style } : {}),
      },
    };
  });
}

export function buildGeminiConversationPayload(params: {
  model: string;
  lines: ConversationDialogueLine[];
  labels: Record<ConversationSpeaker, string>;
  speaker1Voice: string;
  speaker2Voice: string;
  temperature?: number;
}) {
  const structured = usesSpeechMetadata(params.model);
  const parts = structured
    ? buildSpeechMetadataParts(params.lines, params.labels)
    : [{ text: buildLegacyTranscript(params.lines, params.labels) }];
  return {
    contents: [{ role: "user", parts }],
    generationConfig: {
      // Sampling params are ignored from 3.8 on; only send to legacy models.
      ...(structured ? {} : { temperature: params.temperature ?? 1 }),
      responseModalities: ["AUDIO"],
      speechConfig: {
        multiSpeakerVoiceConfig: {
          speakerVoiceConfigs: [
            {
              speaker: params.labels.speaker1,
              voiceConfig: { prebuiltVoiceConfig: { voiceName: params.speaker1Voice } },
            },
            {
              speaker: params.labels.speaker2,
              voiceConfig: { prebuiltVoiceConfig: { voiceName: params.speaker2Voice } },
            },
          ],
        },
      },
    },
  };
}

/** Single-speaker payload (voice previews); text is verbatim on every model. */
export function buildGeminiSinglePayload(params: { text: string; voice: string }) {
  return {
    contents: [{ role: "user", parts: [{ text: params.text }] }],
    generationConfig: {
      responseModalities: ["AUDIO"],
      speechConfig: {
        voiceConfig: { prebuiltVoiceConfig: { voiceName: params.voice } },
      },
    },
  };
}
