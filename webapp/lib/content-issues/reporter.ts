/** First 8 chars, matching clip-feedback's "From …" chip. */
export function shortReporterId(userId: string): string {
  return userId.length <= 8 ? userId : userId.slice(0, 8);
}

export function usageUserHref(userId: string): string {
  return `/usage?uid=${encodeURIComponent(userId)}`;
}
