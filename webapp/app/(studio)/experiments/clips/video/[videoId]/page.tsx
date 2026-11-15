import { ClipVideoEditor } from "@/components/experiments/clips/clip-video-editor";

export default async function ClipVideoPage({
  params,
}: {
  params: Promise<{ videoId: string }>;
}) {
  const { videoId } = await params;
  return <ClipVideoEditor videoId={videoId} />;
}
