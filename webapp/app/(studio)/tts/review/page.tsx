import { Suspense } from "react";
import { ReviewQueue } from "@/components/tts/review-queue";
import { Skeleton } from "@/components/ui/skeleton";

function ReviewQueueFallback() {
  return (
    <div className="flex flex-col gap-4">
      <Skeleton className="h-8 w-64" />
      <Skeleton className="h-32 w-full" />
    </div>
  );
}

export default function ReviewQueuePage() {
  return (
    <div className="flex min-w-0 flex-1 flex-col gap-4">
      <Suspense fallback={<ReviewQueueFallback />}>
        <ReviewQueue />
      </Suspense>
    </div>
  );
}
