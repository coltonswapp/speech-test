import { Suspense } from "react";
import { TrackSidebar } from "@/components/tts/track-sidebar";
import { TrackComposer } from "@/components/tts/track-composer";
import { Skeleton } from "@/components/ui/skeleton";

function TrackComposerFallback() {
  return (
    <div className="flex flex-1 flex-col gap-4">
      <Skeleton className="h-8 w-64" />
      <Skeleton className="h-32 w-full" />
    </div>
  );
}

export default async function TTSTrackPage({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;

  return (
    <div className="flex min-w-0 flex-1 flex-col gap-4 md:flex-row md:gap-6">
      <TrackSidebar activeId={projectId} />
      <Suspense fallback={<TrackComposerFallback />}>
        <TrackComposer projectId={projectId} />
      </Suspense>
    </div>
  );
}
