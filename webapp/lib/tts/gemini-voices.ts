// Client-safe voice list — mirrors GEMINI_TTS_VOICES in gemini-tts.ts (which is
// server-only). Keep in sync if the voice catalog changes.
export const GEMINI_TTS_VOICES = [
  "Zephyr",
  "Puck",
  "Charon",
  "Kore",
  "Fenrir",
  "Leda",
  "Orus",
  "Aoede",
  "Callirrhoe",
  "Autonoe",
  "Enceladus",
  "Iapetus",
  "Umbriel",
  "Algieba",
  "Despina",
  "Erinome",
  "Algenib",
  "Rasalgethi",
  "Laomedeia",
  "Achernar",
  "Alnilam",
  "Schedar",
  "Gacrux",
  "Pulcherrima",
  "Achird",
  "Zubenelgenubi",
  "Vindemiatrix",
  "Sadachbia",
  "Sadaltager",
  "Sulafat",
] as const;

// The same 30 prebuilt voices are accepted by gemini-3.8-flash-tts and
// gemini-3.8-flash-lite-tts (checked 2026-11-02 against the speech-generation docs).
export {
  GEMINI_TTS_DEFAULT_MODEL,
  GEMINI_TTS_MODELS,
  type GeminiTtsModel,
} from "../gemini/models";
