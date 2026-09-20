import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { conversationContentHash } from "./content-hash";
import { scenarioLinesToConversation } from "./scenario-conversation";
import type { DialogueLine } from "@/lib/dialogue/types";

describe("scenarioLinesToConversation delivery", () => {
  const lines: DialogueLine[] = [
    {
      speaker: "Mika",
      japanese: "すみません。",
      delivery: "[softly]",
    },
    {
      speaker: "Kaito",
      japanese: "大丈夫です。",
      delivery: "  ",
    },
  ];

  it("keeps japanese clean and carries delivery separately", () => {
    const conversation = scenarioLinesToConversation(lines);
    assert.deepEqual(conversation.lines, [
      { speaker: "speaker1", text: "すみません。", delivery: "[softly]" },
      { speaker: "speaker2", text: "大丈夫です。" },
    ]);
  });

  it("content hash ignores delivery tags", () => {
    const withDelivery = scenarioLinesToConversation(lines);
    const withoutDelivery = scenarioLinesToConversation(
      lines.map((line) => {
        if (!("japanese" in line)) return line;
        const { delivery: _delivery, ...rest } = line as {
          speaker: string;
          japanese: string;
          delivery?: string;
        };
        return rest;
      })
    );
    assert.equal(
      conversationContentHash(withDelivery.lines),
      conversationContentHash(withoutDelivery.lines)
    );
  });
});
