import { Suspense } from "react";
import { CurriculumView } from "@/components/content/curriculum-view";
import { Skeleton } from "@/components/ui/skeleton";

function CurriculumFallback() {
  return (
    <div className="flex flex-1 flex-col gap-3 p-1">
      <Skeleton className="h-8 w-48" />
      <Skeleton className="h-24 w-full" />
      <Skeleton className="h-24 w-full" />
    </div>
  );
}

export default function CurriculumPage() {
  return (
    <Suspense fallback={<CurriculumFallback />}>
      <CurriculumView />
    </Suspense>
  );
}
