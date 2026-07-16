import { PointList } from "@/components/content/point-list";
import { PointEditor } from "@/components/content/point-editor";

export default async function ContentPointPage({
  params,
}: {
  params: Promise<{ pointId: string }>;
}) {
  const { pointId } = await params;

  return (
    <div className="flex flex-1 gap-6">
      <PointList activeId={pointId} />
      <PointEditor pointId={pointId} />
    </div>
  );
}
