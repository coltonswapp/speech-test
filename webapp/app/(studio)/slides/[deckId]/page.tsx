import { DeckEditor } from "@/components/slides/deck-editor";

export default async function SlideDeckPage({
  params,
}: {
  params: Promise<{ deckId: string }>;
}) {
  const { deckId } = await params;
  return <DeckEditor deckId={deckId} />;
}
