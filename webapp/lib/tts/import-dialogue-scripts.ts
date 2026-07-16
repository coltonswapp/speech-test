import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import {
  dialogueScenario,
  ttsDialogueGroup,
  ttsDialogueLine,
  ttsProject,
} from "@/lib/db/schema";
import type { ImportedCollection } from "@/lib/tts/dialogue-import";
import { GEMINI_TTS_DEFAULT_MODEL } from "@/lib/tts/gemini-voices";

export function slugifyDialogueGroup(input: string): string {
  const slug = input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug || crypto.randomUUID();
}

export async function importDialogueScripts(
  collection: ImportedCollection
): Promise<{
  groupId: string;
  groupTitle: string;
  created: number;
  updated: number;
  trackIds: string[];
}> {
  if (collection.scripts.length === 0) {
    throw new Error("No dialogue scenarios found.");
  }

  const groupId = collection.id
    ? slugifyDialogueGroup(collection.id)
    : slugifyDialogueGroup(collection.title ?? "import");
  const groupTitle = collection.title ?? collection.id ?? "Imported dialogue";

  await db
    .insert(ttsDialogueGroup)
    .values({ id: groupId, title: groupTitle })
    .onConflictDoUpdate({
      target: ttsDialogueGroup.id,
      set: { title: groupTitle },
    });

  let created = 0;
  let updated = 0;
  const trackIds: string[] = [];

  for (const [index, script] of collection.scripts.entries()) {
    // source_scenario_id is a real FK now — only link when the uploaded JSON's
    // scenario id actually exists in dialogue_scenario; otherwise import as an
    // unlinked ad-hoc track.
    const sourceId = script.sourceId
      ? (
          await db.query.dialogueScenario.findFirst({
            where: eq(dialogueScenario.id, script.sourceId),
            columns: { id: true },
          })
        )?.id ?? null
      : null;

    const existing = sourceId
      ? await db.query.ttsProject.findFirst({
          where: eq(ttsProject.sourceScenarioId, sourceId),
        })
      : undefined;

    const promptText = script.lines
      .map((line) => {
        const name =
          line.speaker === "speaker1"
            ? (script.speaker1Name ?? "Speaker 1")
            : (script.speaker2Name ?? "Speaker 2");
        return `${name}: ${line.text}`;
      })
      .join("\n");

    let projectId: string;
    if (existing) {
      await db
        .update(ttsProject)
        .set({
          compositionMode: "conversation",
          provider: "gemini",
          model: GEMINI_TTS_DEFAULT_MODEL,
          promptText,
          speaker1Name: script.speaker1Name,
          speaker2Name: script.speaker2Name,
          trackName: script.title,
          groupId,
          groupOrderIndex: index,
          updatedAt: new Date(),
        })
        .where(eq(ttsProject.id, existing.id));
      projectId = existing.id;
      updated++;
    } else {
      const [project] = await db
        .insert(ttsProject)
        .values({
          compositionMode: "conversation",
          provider: "gemini",
          voice: "Zephyr/Puck",
          model: GEMINI_TTS_DEFAULT_MODEL,
          promptText,
          speaker1Voice: "Zephyr",
          speaker2Voice: "Puck",
          speaker1Name: script.speaker1Name,
          speaker2Name: script.speaker2Name,
          trackName: script.title,
          groupId,
          sourceScenarioId: sourceId,
          groupOrderIndex: index,
        })
        .returning();
      projectId = project.id;
      created++;
    }

    // Scenario-backed projects read lines from dialogue_scenario at
    // generation time; only unlinked tracks keep their own line copies.
    await db
      .delete(ttsDialogueLine)
      .where(eq(ttsDialogueLine.projectId, projectId));
    if (!sourceId) {
      await db.insert(ttsDialogueLine).values(
        script.lines.map((line, lineIndex) => ({
          projectId,
          speaker: line.speaker,
          text: line.text,
          orderIndex: lineIndex,
        }))
      );
    }

    trackIds.push(projectId);
  }

  return { groupId, groupTitle, created, updated, trackIds };
}
