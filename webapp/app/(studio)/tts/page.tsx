import { TrackSidebar } from "@/components/tts/track-sidebar";

export default function TTSStudioPage() {
  return (
    <div className="flex flex-1 gap-6">
      <TrackSidebar />
      <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
        Select a track, or create a new one to get started.
      </div>
    </div>
  );
}
