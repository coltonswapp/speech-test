/**
 * Model-output evaluation for contextual_gloss related words.
 *
 * Not part of the deterministic selftest. Loading this file does not call Gemini.
 * A run spends money; do it only with approval:
 *
 *   RUN_CONTEXTUAL_GLOSS_EVAL=1 npx tsx src/features/contextual_gloss.model-eval.ts
 *
 * Pass: for a transparent compound, the first related words are its real components.
 * 減る may appear only after 人口 and 減少. Non-compounds must not grow invented parts.
 */
import assert from "node:assert/strict";

import { contextualGloss } from "./contextual_gloss.js";

const sentence = "そうですね…最近、人口減少のニュースをよく見ます。";

type Expectation = {
  surface: string;
  sentence: string;
  /** Words that must lead the related list, in order. */
  leads?: string[];
  /** Words that must not appear. */
  absent?: string[];
};

const cases: Expectation[] = [
  {
    surface: "人口減少",
    sentence,
    leads: ["人口", "減少"],
    absent: ["人", "口", "減", "少", "口減"],
  },
  {
    surface: "高速道路",
    sentence: "高速道路を走ります。",
    leads: ["高速", "道路"],
    absent: ["高", "速", "道", "路"],
  },
  {
    surface: "引っ越し",
    sentence: "来月、引っ越しをします。",
    leads: ["引っ越す"],
    absent: ["引っ", "越し"],
  },
  {
    surface: "今日",
    sentence: "今日はいい天気です。",
    absent: ["今", "日"],
  },
  {
    surface: "働く",
    sentence: "兄は東京で働いています。",
    absent: ["働", "く"],
  },
];

async function main() {
  if (process.env.RUN_CONTEXTUAL_GLOSS_EVAL !== "1") {
    console.log(
      `contextual_gloss model eval skipped (${cases.length} cases). Set RUN_CONTEXTUAL_GLOSS_EVAL=1 to call Gemini.`,
    );
    return;
  }

  const apiKey = process.env.GEMINI_API_KEY?.trim();
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY is required when RUN_CONTEXTUAL_GLOSS_EVAL=1");
  }

  const { createGeminiClient } = await import("../gemini.js");
  const client = createGeminiClient(apiKey);
  const failures: string[] = [];

  for (const item of cases) {
    const prompt = contextualGloss.build({
      sentence: item.sentence,
      surface: item.surface,
      framing: "inSentence",
      requestsHeadword: false,
    });
    const generated = await client.generateJSON(contextualGloss.defaultModel, prompt);
    const result = contextualGloss.parseResult(generated.json, {
      sentence: item.sentence,
      surface: item.surface,
      framing: "inSentence",
      requestsHeadword: false,
    });
    const got = result.relatedWords.map((word) => word.word);
    const lead = item.leads ?? [];
    const leadOk = lead.every((word, index) => got[index] === word);
    const absent = (item.absent ?? []).filter((word) => got.includes(word));
    if (!leadOk || absent.length > 0) {
      failures.push(
        `${item.surface}: got [${got.join(", ")}]` +
          (leadOk ? "" : `; wanted [${lead.join(", ")}] first`) +
          (absent.length ? `; unexpected [${absent.join(", ")}]` : ""),
      );
    } else {
      console.log(`${item.surface}: ${got.join(", ") || "(none)"}`);
    }
  }

  assert.deepEqual(failures, []);
}

const isDirectRun = process.argv[1]?.includes("contextual_gloss.model-eval");
if (isDirectRun) {
  main().catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  });
}
