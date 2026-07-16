import { PointList } from "@/components/content/point-list";

export default function ContentStudioPage() {
  return (
    <div className="flex flex-1 gap-6">
      <PointList />
      <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
        Select a grammar point to view or edit it.
      </div>
    </div>
  );
}
