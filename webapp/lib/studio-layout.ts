/**
 * Width where Studio keeps the persistent lesson/scene outline (`w-80`)
 * beside the editor. Matches `--breakpoint-studio-split` in `globals.css`
 * (Tailwind `studio-split:`, 80rem = 1280 CSS px).
 *
 * Tesla in-car Chromium (Model 3/Y landscape) reports ~1100–1254 CSS px
 * after the 2025 devicePixelRatio bump (physical 1920×1200 / ~1.53). Browser
 * chrome can shrink the inner window to ~773×601. The previous `md` (768px)
 * split treated those as desktop and the 320px outline consumed ~40–45% of
 * the viewport (worse with the scene section minimap at `lg`).
 */
export const STUDIO_SPLIT_MIN_WIDTH_PX = 1280;
