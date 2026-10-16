import { formatApiError } from "@/lib/api-error";
import type {
  LessonReportStatus,
  ScenarioReports,
} from "@/lib/lesson-reports/types";

export type ScenarioReportsResponse = {
  configured: boolean;
  configError: string | null;
  scene?: ScenarioReports;
};

async function parse<T>(res: Response): Promise<T> {
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(formatApiError(body, res.status));
  }
  return body as T;
}

export const lessonReportsApi = {
  async getScene(collectionId: string, scenarioId: string) {
    const params = new URLSearchParams({ collectionId, scenarioId });
    return parse<ScenarioReportsResponse>(
      await fetch(`/api/lesson-reports?${params.toString()}`),
    );
  },
  async setStatus(reportId: string, status: LessonReportStatus) {
    return parse<{ ok: true }>(
      await fetch("/api/lesson-reports", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reportId, status }),
      }),
    );
  },
};
