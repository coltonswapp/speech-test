/**
 * Where two transcripts disagree, ignoring punctuation and spacing (same
 * comparison as scripts/clip-asr-compare.ts). Pure.
 */

/** Kana, kanji and digits only: punctuation, spaces and line breaks aren't disagreements. */
export function bareTranscript(lines: string[]): string {
  return lines
    .join("")
    .replace(/[^\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}ー0-9０-９]/gu, "");
}

/** Differing stretches between two strings (character LCS), with a little context from `a`. */
export function transcriptDifferences(a: string, b: string): string[] {
  const n = a.length;
  const m = b.length;
  const dp = Array.from({ length: n + 1 }, () => new Uint16Array(m + 1));
  for (let i = n - 1; i >= 0; i--)
    for (let j = m - 1; j >= 0; j--)
      dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
  const out: string[] = [];
  let i = 0;
  let j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && a[i] === b[j]) {
      i++;
      j++;
      continue;
    }
    const i0 = i;
    const j0 = j;
    while ((i < n || j < m) && !(i < n && j < m && a[i] === b[j])) {
      if (j >= m || (i < n && dp[i + 1][j] >= dp[i][j + 1])) i++;
      else j++;
    }
    const before = a.slice(Math.max(0, i0 - 6), i0);
    const after = a.slice(i, i + 6);
    out.push(`…${before}[${a.slice(i0, i) || "∅"} → ${b.slice(j0, j) || "∅"}]${after}…`);
  }
  return out;
}
