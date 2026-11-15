/** "5:12.3", "1:05:12" or "312.3" → seconds; null when unparseable. */
export function parseTimecode(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const parts = trimmed.split(":");
  if (parts.length > 3 || parts.some((p) => !/^\d+(\.\d+)?$/.test(p))) return null;
  return parts.reduce((total, part) => total * 60 + Number(part), 0);
}

export function formatTimecode(seconds: number): string {
  const sign = seconds < 0 ? "-" : "";
  const abs = Math.abs(seconds);
  const m = Math.floor(abs / 60);
  const s = abs - m * 60;
  return `${sign}${m}:${s.toFixed(2).padStart(5, "0")}`;
}

/** Accepts a bare 11-char id or any youtube.com / youtu.be URL. */
export function parseYouTubeId(value: string): string | null {
  const trimmed = value.trim();
  if (/^[A-Za-z0-9_-]{11}$/.test(trimmed)) return trimmed;
  try {
    const url = new URL(trimmed);
    if (url.hostname === "youtu.be") return url.pathname.slice(1, 12) || null;
    const v = url.searchParams.get("v");
    if (v) return v;
    const match = /\/(?:embed|shorts|live)\/([A-Za-z0-9_-]{11})/.exec(url.pathname);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}
