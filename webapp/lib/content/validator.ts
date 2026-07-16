import type { GrammarPointInput } from "@/lib/content/types";

// Ported from GrammarContentKit/Sources/GrammarContentKit/ContentValidator.swift

export type ValidationIssue = { message: string };

const deprecatedDrillKinds = new Set([
  "sentenceBuilder",
  "formChoice",
  "precursorChoice",
  "sentenceChoice",
  "meaningChoice",
]);

function resolvedPattern(point: GrammarPointInput): string {
  return point.pattern?.trim() || point.title;
}

function resolvedShortDefinition(point: GrammarPointInput): string {
  return point.shortDefinition?.trim() || point.headlineEnglish;
}

function resolvedContrastDrills(point: GrammarPointInput) {
  if (point.contrastDrills && point.contrastDrills.length > 0) {
    return point.contrastDrills;
  }
  return point.drills
    .filter((d) => d.kind === "contrastChoice")
    .map((d) => ({
      contrastLabel: d.contrastLabel ?? "",
      choices: d.choices ?? [],
      correctChoice: d.correctChoice ?? "",
      ruleTargeted: d.instruction ?? null,
    }));
}

export function validatePoint(point: GrammarPointInput): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  if (!point.id.trim()) {
    issues.push({ message: "Point missing id" });
  }
  if (!resolvedPattern(point).trim()) {
    issues.push({ message: `${point.id}: missing pattern/title` });
  }
  if (!resolvedShortDefinition(point).trim()) {
    issues.push({ message: `${point.id}: missing shortDefinition/headlineEnglish` });
  }
  if (point.examples.length === 0) {
    issues.push({ message: `${point.id}: needs at least one example` });
  }
  if (point.examples.length > 10) {
    issues.push({ message: `${point.id}: too many examples (${point.examples.length})` });
  }

  resolvedContrastDrills(point).forEach((drill, index) => {
    if (!drill.correctChoice.trim()) {
      issues.push({ message: `${point.id}: contrastDrill ${index} missing correctChoice` });
    }
    if (!drill.choices.includes(drill.correctChoice)) {
      issues.push({ message: `${point.id}: contrastDrill ${index} correctChoice not in choices` });
    }
  });

  for (const drill of point.drills) {
    if (drill.kind !== "contrastChoice" && deprecatedDrillKinds.has(drill.kind)) {
      issues.push({
        message: `${point.id}: deprecated drill kind ${drill.kind} — remove before merge`,
      });
    }
  }

  return issues;
}

export function validatePoints(points: GrammarPointInput[]): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const ids = new Set<string>();
  const indices: number[] = [];

  for (const point of points) {
    issues.push(...validatePoint(point));
    if (ids.has(point.id)) {
      issues.push({ message: `Duplicate id: ${point.id}` });
    }
    ids.add(point.id);
    indices.push(point.orderIndex);
  }

  const sorted = [...indices].sort((a, b) => a - b);
  if (!indices.every((v, i) => v === sorted[i])) {
    issues.push({ message: "orderIndex values are not sorted" });
  }
  if (new Set(indices).size !== indices.length) {
    issues.push({ message: "Duplicate orderIndex values" });
  }

  return issues;
}
