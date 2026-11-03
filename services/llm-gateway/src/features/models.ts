/**
 * Default for the five learner features that were on `gemini-2.5-flash`.
 * `contextual_gloss` and `sense_fit` stay on `gemini-2.5-flash-lite` (see those files).
 * Per-feature env `GEMINI_MODEL_<FEATURE>` still overrides this.
 */
export const GEMINI_35_FLASH_LITE = "gemini-3.5-flash-lite";

/** Kana readings: pronounced particles, including inside fixed expressions. */
export const PARTICLE_READING_RULE =
  "Particles are read as pronounced, not as spelled: topic は → わ, direction へ → え, object を → お. This holds inside fixed expressions and merged tokens too (こんにちは → こんにちわ, こんばんは → こんばんわ, では → でわ, には → にわ). A は or へ that is part of a word keeps its own reading (はい → はい, へえ → へえ, 母 → はは, 部屋 → へや).";
