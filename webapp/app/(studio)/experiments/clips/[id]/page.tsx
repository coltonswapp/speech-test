import { ClipEditor } from "@/components/experiments/clips/clip-editor";

export default async function ClipPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <ClipEditor clipId={id} />;
}
