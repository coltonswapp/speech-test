import { formatApiError } from "@/lib/api-error";
import type { UsagePeriodSnapshot } from "@/lib/usage/parse-period";
import type { UsagePeriod } from "@/lib/usage/period-keys";

export type UsageApiResponse = {
  period: UsagePeriod;
  periodDocId: string;
  configured: boolean;
  configError: string | null;
  credentialSource: string | null;
  projectId: string | null;
  product: UsagePeriodSnapshot;
  user: UsagePeriodSnapshot | null;
};

export const usageApi = {
  async get(args: {
    period: UsagePeriod;
    uid?: string;
  }): Promise<UsageApiResponse> {
    const params = new URLSearchParams({ period: args.period });
    const uid = args.uid?.trim();
    if (uid) params.set("uid", uid);

    const res = await fetch(`/api/usage?${params.toString()}`);
    const body = await res.json().catch(() => null);
    if (!res.ok) {
      throw new Error(formatApiError(body, res.status));
    }
    return body as UsageApiResponse;
  },
};
