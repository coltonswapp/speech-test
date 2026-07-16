export const dialogueFormalityLevels = [
  "casual",
  "polite",
  "formal",
  "very-formal",
] as const;

export type DialogueFormality = (typeof dialogueFormalityLevels)[number];

export const dialogueFormalityLabels: Record<DialogueFormality, string> = {
  casual: "Casual",
  polite: "Polite",
  formal: "Formal",
  "very-formal": "Very formal",
};

export const dialogueFormalityHints: Record<DialogueFormality, string> = {
  casual: "Plain form (だ/る) — friends, family, close peers",
  polite: "Desu/masu form — the default polite register for most situations",
  formal: "Formal desu/masu with fewer contractions — strangers, customers, work",
  "very-formal": "Keigo (敬語) — sonkeigo/kenjougo for superiors, ceremony, business",
};

export function dialogueFormalityPrompt(formality: DialogueFormality): string {
  switch (formality) {
    case "casual":
      return [
        "Formality: Casual (plain form).",
        "Use plain-form verbs and copulas (だ/る, not です/ます) as appropriate for close friends, family, or peers.",
        "Allow casual contractions and particles dropped where natural in speech.",
        "Avoid stiff or distancing polite language unless a specific line calls for it.",
      ].join(" ");
    case "polite":
      return [
        "Formality: Polite (desu/masu form).",
        "Use standard です/ます polite form throughout, the default register for most everyday interactions.",
        "Keep it friendly and approachable, not stiff or overly deferential.",
      ].join(" ");
    case "formal":
      return [
        "Formality: Formal.",
        "Use consistent です/ます polite form with fewer contractions and more careful phrasing.",
        "Appropriate for talking with strangers, customers, or in a professional context.",
        "Avoid casual slang or abbreviated speech patterns.",
      ].join(" ");
    case "very-formal":
      return [
        "Formality: Very formal (keigo).",
        "Use honorific (sonkeigo) and humble (kenjougo) keigo where appropriate, alongside polite です/ます form.",
        "Appropriate for addressing superiors, formal business settings, or ceremonial occasions.",
        "Keep it respectful and precise; avoid any casual contractions or plain form.",
      ].join(" ");
  }
}
