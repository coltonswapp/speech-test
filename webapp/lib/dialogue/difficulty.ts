export const dialogueDifficultyLevels = [
  "beginner",
  "intermediate",
  "advanced",
  "expert",
] as const;

export type DialogueDifficulty = (typeof dialogueDifficultyLevels)[number];

export const dialogueDifficultyLabels: Record<DialogueDifficulty, string> = {
  beginner: "Beginner",
  intermediate: "Intermediate",
  advanced: "Advanced",
  expert: "Expert",
};

export const dialogueDifficultyHints: Record<DialogueDifficulty, string> = {
  beginner: "JLPT N5 — very common words, short polite sentences",
  intermediate: "JLPT N4–N3 — everyday vocabulary, natural but accessible",
  advanced: "JLPT N2+ — richer vocabulary and longer turns",
  expert: "Near-native — idiomatic, nuanced, still spoken and natural",
};

export function dialogueDifficultyPrompt(difficulty: DialogueDifficulty): string {
  switch (difficulty) {
    case "beginner":
      return [
        "Difficulty: Beginner (JLPT N5).",
        "Use only high-frequency, beginner-safe vocabulary and grammar.",
        "Prefer short spoken sentences, basic politeness, and concrete everyday words.",
        "Avoid rare kanji compounds, slang, idioms, and abstract phrasing.",
      ].join(" ");
    case "intermediate":
      return [
        "Difficulty: Intermediate (around JLPT N4–N3).",
        "Use common everyday vocabulary with some variety, but stay learner-friendly.",
        "Allow moderately longer turns and natural spoken phrasing without becoming literary.",
        "Avoid highly specialized, literary, or obscure vocabulary.",
      ].join(" ");
    case "advanced":
      return [
        "Difficulty: Advanced (around JLPT N2+).",
        "Use richer, more natural vocabulary and longer spoken turns while staying clear.",
        "Include more nuanced expressions and realistic native-like phrasing where appropriate.",
        "Still avoid needlessly obscure or literary language.",
      ].join(" ");
    case "expert":
      return [
        "Difficulty: Expert (near-native spoken Japanese).",
        "Use idiomatic, natural native-level vocabulary and phrasing appropriate to the setting.",
        "Allow contractions, discourse markers, and realistic colloquial speech when the scene fits.",
        "Keep the dialogue spoken and believable, not academic or literary.",
      ].join(" ");
  }
}
