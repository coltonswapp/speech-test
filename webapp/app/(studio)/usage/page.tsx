import { UsageView } from "@/components/usage/usage-view";

export default async function UsagePage({ searchParams }: { searchParams: Promise<Record<string, string>> }) {
  const uid = (await searchParams).uid?.trim();
  return <UsageView initialUid={uid || undefined} />;
}
