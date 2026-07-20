/**
 * Scrolls to the element with the given id in a fixed, short duration
 * regardless of distance — native `scrollIntoView({ behavior: "smooth" })`
 * scales its duration with distance and reads as sluggish on long pages.
 */
export function scrollToId(
  id: string,
  options?: { offset?: number; duration?: number },
) {
  const el = document.getElementById(id);
  if (!el) return;

  const offset = options?.offset ?? 80;
  const duration = options?.duration ?? 300;
  const startY = window.scrollY;
  const targetY = el.getBoundingClientRect().top + startY - offset;
  const startTime = performance.now();

  function step(now: number) {
    const t = Math.min((now - startTime) / duration, 1);
    const eased = 1 - Math.pow(1 - t, 3); // easeOutCubic
    window.scrollTo(0, startY + (targetY - startY) * eased);
    if (t < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}
