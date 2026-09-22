export type HighlightColor = {
  id: string;
  title: string;
  css: string;
};

export const HIGHLIGHT_COLORS: HighlightColor[] = [
  { id: "yellow", title: "Yellow", css: "rgba(255, 204, 0, 0.55)" },
  { id: "blue", title: "Blue", css: "rgba(0, 122, 255, 0.55)" },
  { id: "pink", title: "Pink", css: "rgba(255, 45, 85, 0.55)" },
  { id: "orange", title: "Orange", css: "rgba(255, 149, 0, 0.55)" },
  { id: "green", title: "Green", css: "rgba(52, 199, 89, 0.55)" },
  { id: "teal", title: "Teal", css: "rgba(48, 176, 199, 0.55)" },
  { id: "purple", title: "Purple", css: "rgba(175, 82, 222, 0.55)" },
  { id: "mint", title: "Mint", css: "rgba(0, 199, 190, 0.55)" },
  { id: "indigo", title: "Indigo", css: "rgba(88, 86, 214, 0.55)" },
  { id: "red", title: "Red", css: "rgba(255, 59, 48, 0.55)" },
  { id: "gray", title: "Gray", css: "rgba(142, 142, 147, 0.55)" },
];

export const DEFAULT_HIGHLIGHT_COLOR = "yellow";

export function highlightCss(id: string): string {
  return (
    HIGHLIGHT_COLORS.find((color) => color.id === id)?.css ??
    HIGHLIGHT_COLORS[0].css
  );
}
