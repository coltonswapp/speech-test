export const issueSubjects = ["clip", "scene"] as const;
export type IssueSubject = (typeof issueSubjects)[number];

export function parseIssueId(value: string): { subject: IssueSubject; key: string } | null {
  const separator = value.indexOf("-");
  if (separator < 0) return null;
  const subject = issueSubjects.find(candidate => candidate === value.slice(0, separator));
  const key = value.slice(separator + 1);
  return subject && /^[a-zA-Z0-9_-]{1,128}$/.test(key) ? { subject, key } : null;
}

export function clipEditorHref(clipId: string) {
  return "/experiments/clips/" + encodeURIComponent(clipId);
}

export function sceneEditorHref(collectionId: string, scenarioId: string) {
  return "/content/dialogues/" + encodeURIComponent(collectionId) + "/" + encodeURIComponent(scenarioId);
}
