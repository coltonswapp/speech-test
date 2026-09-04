import { TrackSidebar } from "@/components/tts/track-sidebar";
import { TrackComposer } from "@/components/tts/track-composer";

export default async function TTSTrackPage({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;

  return (
    <div className="flex min-w-0 flex-1 flex-col gap-4 md:flex-row md:gap-6">
      <TrackSidebar activeId={projectId} />
      <TrackComposer projectId={projectId} />
    </div>
  );
}
