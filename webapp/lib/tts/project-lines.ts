// Which lines a TTS project speaks. Scenario-backed projects read the
// scenario's current lines; ad-hoc tracks keep their own tts_dialogue_line
// rows. Shared by take generation and auto-stamp so both see the same script
// (and therefore the same contentHash).
import { asc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { dialogueScenario, ttsDialogueLine, ttsProject } from "@/lib/db/schema";
import { scenarioLinesToConversation } from "@/lib/tts/scenario-conversation";
import type { ConversationLine } from "@/lib/tts/scenario-conversation";
import type { DialogueLine as ScenarioDialogueLine } from "@/lib/dialogue/types";

export class UserFacingError extends Error {}

// Scenario-backed projects speak the scenario's current lines; ad-hoc tracks
// keep their own tts_dialogue_line rows.
export async function loadConversationLines(
  project: typeof ttsProject.$inferSelect
): Promise<ConversationLine[]> {
  if (project.sourceScenarioId) {
    const scenario = await db.query.dialogueScenario.findFirst({
      where: eq(dialogueScenario.id, project.sourceScenarioId),
    });
    if (!scenario) {
      throw new UserFacingError("Source scenario no longer exists.");
    }
    const conversation = scenarioLinesToConversation(
      scenario.lines as ScenarioDialogueLine[]
    );
    if (conversation.lines.length === 0) {
      throw new UserFacingError(
        "The scenario has no dialogue lines with a speaker and Japanese text."
      );
    }
    // Keep the project's display fields in sync with the scenario so the TTS
    // sidebar reflects what was actually spoken.
    await db
      .update(ttsProject)
      .set({
        speaker1Name: conversation.speaker1Name,
        speaker2Name: conversation.speaker2Name,
        promptText: conversation.lines
          .map((line) => {
            const name =
              line.speaker === "speaker1"
                ? (conversation.speaker1Name ?? "Speaker 1")
                : (conversation.speaker2Name ?? "Speaker 2");
            const delivery = line.delivery?.trim();
            const spoken = delivery
              ? `${delivery} ${line.text}`
              : line.text;
            return `${name}: ${spoken}`;
          })
          .join("\n"),
        updatedAt: new Date(),
      })
      .where(eq(ttsProject.id, project.id));
    return conversation.lines;
  }

  const lines = await db.query.ttsDialogueLine.findMany({
    where: eq(ttsDialogueLine.projectId, project.id),
    orderBy: [asc(ttsDialogueLine.orderIndex)],
  });
  return lines
    .filter((l) => l.text.trim().length > 0)
    .map((l) => ({
      speaker: l.speaker as "speaker1" | "speaker2",
      text: l.text,
    }));
}
