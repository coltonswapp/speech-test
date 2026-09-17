# Dialogue tab UX: auto-scroll to current lesson, pinned Daily Dialogue strip, fast thumbnails

## Context

The Dialogue tab (`shizen/Dialogue/DialogueHomeViewController.swift`) embeds the sine-path lesson list (`shizen/Experiments/LanguageProgressSnakeExperimentViewController.swift`) edge to edge, with the Daily Dialogue card handed in as a scrolling banner. Three UX problems, all verified in code:

1. **No progress on the path.** `LessonUnitSectionBuilder.pathLesson(from:)` maps every CMS lesson to `state: .current`, `completedParts: 0`. The path never shows completed lessons, never identifies the "next" lesson, and always opens at the top. The data exists locally: `DialogueProgressStore.completedScenarioIDs` holds scenario IDs namespaced `"<lessonId>/<slug>"` (CMS `scenarios/route.ts:29`, bundled `train-station.json`), and the index gives `scenarioCount` per lesson. No server change needed for progress.
2. **Daily Dialogue vanishes once we auto-scroll.** The card is a plain subview of the collection view at content y=16 (`updateHeaderBannerLayout`), so it scrolls away. It is not pinned today; the top inset under the tab bar comes from `MainViewController.applyMainTabScrollInsets` → `MainTabScrollable.applyMainTabTopInset`.
3. **Thumbnails load late and cost a lot.** Live CDN: 5 lesson thumbnails, each 2.3–2.7 MB PNG (1402×1122), displayed in a ~103pt circle. `LessonThumbnailLoader` (`shizen/Dialogue/LessonWaterfallGrid.swift:487-517`) is NSCache-only with no cost limit, uses `URLSession.shared` (default URLCache refuses responses over ~5% of its ~10 MB disk capacity, so 2.5 MB PNGs are re-downloaded every launch), decodes lazily on the main thread at full size (~6 MB RAM each), has no in-flight dedup, and no prefetch. Loads start only when a cell is configured on screen. Locked stones run a CIContext grayscale on the main thread per configure, re-run for every visible stone on every tip show/dismiss (`reconfigureVisibleStones`).

Also: launch shows `PathUnit.sampleCurriculum` (fake data) until the network index arrives, because the index is never cached on disk (per-collection JSON is: `ContentCMSClient.readCachedCollectionData`).

**User decisions (final):**
- Auto-scroll to the current / in-progress lesson on launch and after finishing a lesson.
- Daily Dialogue: full card stays at the top of the content; when it scrolls out, a slim pinned strip slides in under the tab bar and stays. Unit headers pin below the strip.
- Lessons after the current one are **locked** (grayscale, lock icon, not startable).
- Images: iOS downsample + disk cache + prefetch + dedup, **and** the webapp writes small WebP variants at upload (sharp), with a one-off migration for existing thumbnails.

---

## Part 1 — Wire real progress into the path (iOS)

**Files:** `shizen/Dialogue/LessonUnitSections.swift`, `shizen/Dialogue/DialogueHomeViewController.swift`, snake VC (`PathLesson`/`PathUnit`, `LessonTitleTipView`)

- Add `LessonUnitSectionBuilder.pathUnits(from index:, completedScenarioIDs: Set<String>) -> [PathUnit]`; keep the existing signature delegating with an empty set (used by the CMS grid screen).
  - Filter out lessons with `scenarioCount == 0` (otherwise one becomes a permanent "current" that opens an empty picker).
  - Per lesson: `completedParts = min(scenarioCount, count of ids with prefix "\(id)/")`.
  - Walk lessons in curriculum order (units in order, then the unfiled "More lessons" section): all parts done → `.completed`; first not-completed → `.current` (carry `completedParts` so the ring shows in-progress); everything after → `.locked`.
  - Prefer the new `thumbnailSmallUrl` (Part 6) over `thumbnailUrl` for `thumbnailURL`, falling back when absent.
- Make `PathLesson` and `PathUnit` `Equatable` (check `DialogueBubbleUnderglowColor` is) so `setUnits` can early-return on identical data (Part 3).
- `PathUnit.initialIndexPath(in:)`: when nothing is `.current` (all complete), fall back to the **last** `.completed` lesson instead of `(0,0)`.
- `DialogueHomeViewController`: retain the decoded `CMSDialogueLessonIndex` in `latestIndex`; add `rebuildPathUnits()` that calls the builder with `progressStore.completedScenarioIDs` and `lessonPathController.setUnits(_:)`. Call it when the index arrives (cache or network) and in `viewWillAppear` after the existing `progressStore.reload()`, so completing a lesson updates the path on pop.
- **Progress backend (Firebase comes later, no stub needed):** the path only needs "which scenario IDs are completed", which the local file-backed store already provides. Keep the local store as the source of truth (Firebase later becomes a sync layer writing into/out of it; the UI keeps reading local, synchronously). Two seams now so that drop-in is clean:
  - Add `protocol LessonProgressProviding { var completedScenarioIDs: Set<String> { get }; func completedCountToday() -> Int }` in `DialogueProgressStore.swift`; the store conforms; `pathUnits(from:progress:)` and the home VC take the protocol, not the concrete store.
  - Add `static let didChange = Notification.Name("DialogueProgressStore.didChange")`, posted from `markCompleted` and `resetAll` (and later from remote sync). `DialogueHomeViewController` observes it and calls `rebuildPathUnits()` + `refreshDailyDialogueCard()`, in addition to `viewWillAppear`.
  - Keep per-scenario completion as the unit of record and derive lesson state on device, so the eventual Firestore shape is just a set of scenario IDs per user.
- Locked stones: `selectLesson` currently pops the tip with a live "Start Lesson" button for any state, and `openLesson` silently ignores locked. Add a locked mode to `LessonTitleTipView.apply(...)` (hide Start, subtitle "Finish the previous lesson to unlock") and use it in `showLessonTip` when `lesson.state == .locked`.

## Part 2 — Cache the lesson index on disk (iOS)

**File:** `shizen/Content/ContentCMSClient.swift`

- Extract `parseLessonIndex(_ data: Data) throws -> CMSDialogueLessonIndex` from the decode/sort block in `fetchDialogueLessonIndex` (lines 88-106).
- Mirror `readCachedCollectionData`/`writeCachedCollectionData` for `ContentCache/dialogues/index.json`; write on network success; add `cachedDialogueLessonIndex() -> CMSDialogueLessonIndex?` (sync read of a small file).
- Add optional `thumbnailSmallUrl: String?` to `CMSDialogueLessonSummary` and `LessonSummaryRecord`.
- `DialogueHomeViewController.viewDidLoad`: if a cached index exists, build units from it immediately (before first layout); then fetch the network index and rebuild. `sampleCurriculum` stays as the fallback only when the CMS is unconfigured.

## Part 3 — Auto-scroll to the current lesson (iOS)

**File:** `shizen/Experiments/LanguageProgressSnakeExperimentViewController.swift`

Verified lifecycle: all `viewDidLoad`s run during `MainViewController.installPages` with zero-size views; the tab inset is applied in `MainViewController.viewDidLayoutSubviews` (once, gated on safe area). Changing `contentInset` does **not** re-run the snake VC's `viewDidLayoutSubviews`, and `setUnits` → `reloadData` leaves `layoutAttributesForItem` stale until the next `prepare()`. So:

- Add a `LessonPathCollectionView: UICollectionView` subclass with `onDidLayout: (() -> Void)?` called at the end of `layoutSubviews()` (runs after `prepare()` with final bounds, inset and contentSize, for every bounds/inset/reload change). Create it at the existing construction site (line ~182).
- API: `func scrollToCurrentLesson(animated: Bool)` stores `pendingScroll = (PathUnit.initialIndexPath(in: units), animated)` and calls `performPendingScrollIfPossible()`. `setUnits` never scrolls; it early-returns when units are `==` (so tab switches / `viewWillAppear` rebuilds don't close an open tip or reload).
- `performPendingScrollIfPossible()` (called from `onDidLayout`) requires: `bounds.width > 0`, `contentInset.top > 0` when `!managesContentInsets` (this guarantees `applyMainTabTopInset` and its offset reset already ran), `headerBannerView == nil || sineLayout.bannerHeight > 0`, `contentSize.height > 0`, and `sineLayout.layoutAttributesForItem(at: target) != nil`. Then: `visibleH = bounds.height - insetTop - insetBottom`; `offsetY = stone.midY - insetTop - 0.4 * visibleH`; clamp to `[-insetTop, max(-insetTop, contentSize.height - bounds.height + insetBottom)]`; `setContentOffset(_, animated:)`. Do not use `scrollToItem` (can't do the 40% placement).
- `userDidScroll = true` in `scrollViewWillBeginDragging`; clear any pending non-explicit scroll there so a network refresh never yanks the user.
- Home VC sequencing: when `ContentCMSClient.isConfigured`, call `scrollToCurrentLesson(animated: false)` only after the first `setUnits` with real data (cache or network), never for `sampleCurriculum`; when unconfigured, call it in `viewDidLoad`.
- Return from a lesson: appearance callbacks reach both pages, so `viewWillAppear` rebuilds units; if `initialIndexPath` differs from `lastScrollTarget`, set a flag and call `scrollToCurrentLesson(animated: true)` in `viewDidAppear` so the animation plays after the pop transition.
- Do not auto-present the lesson tip on launch; the `.current` ring is the highlight.

## Part 4 — Collapsing pinned Daily Dialogue strip (iOS)

**Files:** `shizen/Dialogue/DialogueHomeViewController.swift`, snake VC + `LessonSinePathLayout`

- New `DailyDialogueCompactStripView` (next to `DailyDialogueCardView`): card surface (`ExperimentPalette.cardSurface/cardBorder`), "Daily Dialogue" title, trailing "n/3 today" (`progressStore.completedCountToday()` / `DialogueProgressStore.scenariosPerDay`) and a small Start capsule (`Colors.brandYellow`). Height ≈ 48pt. Body tap scrolls to top; Start calls `startTodaysDialogue`. `refreshDailyDialogueCard()` configures both card and strip.
- Snake VC: `setCompactHeaderBanner(_ view: UIView?)`. The strip is inserted **inside the collection view** like `headerBannerView` (so the lesson tip at z=50 can still cover it), with `layer.zPosition = 40` (above headers at 30). Positioned in `scrollViewDidScroll` and `updateHeaderBannerLayout`: `y = contentOffset.y + contentInset.top - stripH + progress * stripH` (content coords), alpha = progress; hidden + `accessibilityElementsHidden` when progress == 0. It slides out from under the tab bar through the top edge effect.
- `LessonSinePathLayout`: add `compactStripHeight` and `bannerCardBottomY` (set from `updateHeaderBannerLayout`: `16 + cardHeight`, i.e. `bannerHeight - 24`) and a pure `compactStripProgress(pinY:) = clamp((pinY - bannerCardBottomY) / compactStripHeight, 0, 1)` computed from `contentOffset` inside the layout (no ordering dependency on `scrollViewDidScroll`). `pinnedHeaders(intersecting:)` pins at `pinY + progress * stripH`; `stuckSection(at:)` receives the same shifted line so the unit haptic matches the visual pin. Layout already invalidates on every bounds change, so this is free.
- Expected visual: the first unit header reaches the pin line before the strip is fully in and gets pushed down by up to `stripH` during the transition. That is the requested behavior.
- `MainViewController.handleMainTabVerticalScroll` needs no change (tab bar height is constant; only inactive tabs collapse).

## Part 5 — Thumbnail loader rewrite (iOS)

**Files:** new `shizen/Dialogue/LessonThumbnailLoader.swift` (delete the enum from `LessonWaterfallGrid.swift:485-517`), stone cell in the snake VC, `LessonWaterfallGrid.swift` card cell

- API: `load(url:targetPixelSize: CGFloat?, variant: .color | .grayscale, completion:)`, `cachedImage(for:targetPixelSize:variant:)`, `prefetch(_ urls:, targetPixelSize:)`, `bundledImage(named:targetPixelSize:variant:)`. Keep `cachedImage(for:)` and `load(url:completion:)` as forwarding overloads (`nil`, `.color`) so `DialogueExperimentViewController.swift:670-694` (full-width scene image, must stay full-res) keeps compiling unchanged.
- Disk: dedicated `URLSession` whose configuration uses `URLCache(memoryCapacity: 2 MB, diskCapacity: 100 MB, directory: Caches/LessonThumbnails)` and `requestCachePolicy = .returnCacheDataElseLoad`. R2 sends `Cache-Control: public, max-age=31536000, immutable` (`published-r2.ts`), URLs are content-hashed, so never revalidate. The 100 MB capacity gives a ~5 MB per-response threshold, covering today's PNGs. Do **not** copy `RemoteAudioCache` (semaphore-blocked serial downloads, wrong shape for many small images).
- Decode on a utility queue with `CGImageSourceCreateThumbnailAtIndex` (`kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceThumbnailMaxPixelSize`, `kCGImageSourceCreateThumbnailWithTransform`, `kCGImageSourceShouldCacheImmediately`). Grayscale computed on the same queue from the already-downsampled bitmap. Cache key `"\(url)|\(px)|\(variant)"` (`asset:<name>|…` for bundled). NSCache `totalCostLimit` ≈ 40 MB (cost = bytes).
- In-flight coalescing `[key: [completion]]` under a lock (same pattern as `DialogueScenarioCollectionCatalog.inFlightCompletions`).
- `LessonStoneCell.apply`: request `targetPixelSize = visualSize * UIScreen.main.scale`, variant by state; delete both CIContext helpers (stone cell ~1363-1375 and waterfall card ~337-350); cells do zero image processing, so `reconfigureVisibleStones` becomes cache hits. Keep the `accessibilityIdentifier` reuse-token pattern.
- Snake VC `setUnits`: prefetch all lesson URLs ordered by distance from `initialIndexPath` (closest first). Lesson count is small (9 today), so prefetch-all suffices; no `UICollectionViewDataSourcePrefetching`.
- Side fix: `LessonWaterfallGrid.swift:431-445` height measurement builds a throwaway cell whose `configure` starts a network load; skip the load when measuring.

## Part 6 — Server-side thumbnail variants (webapp, pnpm)

**Blocking finding:** `thumbnailUrl` also feeds the full-width scene image in the dialogue player (`DialogueNestedPagingExperimentViewController.swift:1075` via `DialogueScenarioCollection.thumbnailURL(for:)`). So the small variant must be a **new field**, not a replacement.

**Files:** `webapp/lib/db/schema.ts`, `webapp/lib/dialogue/public-api.ts`, `webapp/lib/storage/published-r2.ts` (+ new `published-r2-core.ts`), new `webapp/lib/images/thumbnail-variants.ts`, both thumbnail routes under `webapp/app/api/content/dialogues/`, new `webapp/scripts/migrate-thumbnails.ts`, `webapp/package.json`

- Read `node_modules/next/dist/docs/01-app/01-getting-started/15-route-handlers.md` first (AGENTS.md: this Next.js differs from training data; keep the existing `RouteContext<"…">` typing).
- `pnpm add sharp`.
- Schema: add `thumbnailSmallUrl` (`thumbnail_small_url`) to `dialogueCollection` and `dialogueScenario`; `pnpm db:generate` + `pnpm db:push`. Expose `thumbnailSmallUrl` in `listPublicDialogueCollections` (and the collection file for future use).
- `thumbnail-variants.ts`: `makeThumbnailVariants(bytes) -> { full: {buffer, key suffix ".webp", max 1600px, q≈82}, small: {"-512.webp", 512px inside, no enlargement} }` via sharp (`.rotate()` for EXIF). Also a shared `publishThumbnail(objectKeyBase, bytes)` that uploads both and returns both URLs, used by both routes (they are near-identical today; see the diff).
- Both POST routes: validate as today, then `publishThumbnail`, store `thumbnailUrl` = full WebP, `thumbnailSmallUrl` = 512 WebP. DELETE clears both.
- Split the S3 code into `lib/storage/published-r2-core.ts` (no `server-only` marker); `published-r2.ts` keeps the marker and re-exports. The migration script imports the core module plus `lib/db/standalone-client` (pattern: `scripts/cleanup-scenario-links.ts:12`).
- `scripts/migrate-thumbnails.ts` + `"db:migrate-thumbnails": "dotenv -e .env.local -- tsx scripts/migrate-thumbnails.ts"`: for every row with a `thumbnailUrl`, fetch it, produce both variants, upload, update both columns; skip rows already `.webp` with `thumbnailSmallUrl` (idempotent); leave old objects in place (immutable URLs). Run against a dev DB first.
- iOS needs no WebP-specific work (ImageIO decodes WebP).

---

## Implementation order

1. Part 1 + Part 2 (progress states, index cache) — visible immediately, no layout risk.
2. Part 3 (auto-scroll).
3. Part 4 (strip).
4. Part 5 (loader).
5. Part 6 (webapp), run the migration, confirm the app receives `thumbnailSmallUrl`.

## Existing PNGs on the CDN

Nothing handles this today. Part 6's `scripts/migrate-thumbnails.ts` is the solution: it re-encodes every existing collection/scenario thumbnail (5 today) into the two WebP variants, uploads them, and updates both columns. Idempotent; old PNG objects are left in place.

## Test checklist (user runs builds and verification; Claude does not run xcodebuild)

Build the `shizen` scheme on the iPhone 17 Pro simulator after each part lands. Ignore the `shizen-chinese` target entirely.

- Auto-scroll: delete app → cold launch shows no jump until real data lands, then the current stone sits ~40% down with the top inset respected; relaunch with cache → lands immediately; switch to Practice and back → no re-scroll, open tip persists; drag before data arrives → no re-scroll; rotate → stays sane.
- Progress: complete all scenarios of the current lesson → pop → animated scroll to the next; previous shows the badge; remaining are grayscale + lock; tapping a locked stone shows the locked tip without Start; all-complete case lands on the last lesson.
- Strip: slow scroll past the card → strip slides in exactly as the card's bottom crosses the tab bar; unit header pins beneath it; reverses on scroll up; Start launches today's dialogue; `n/3` updates after a scenario; the tip is never covered; VoiceOver skips the hidden strip.
- Images: first launch → one request per thumbnail; airplane-mode relaunch → thumbnails still appear (`URLCache.currentDiskUsage > 0`); Instruments Animation Hitches during tip open/close and scroll are clean; decoded image memory is ~512px-sized.
- Webapp: `pnpm lint && pnpm build`; upload a PNG in Studio → response has both URLs and R2 objects are `image/webp`; migration on dev DB, re-run is a no-op; `GET /api/public/dialogues` returns `thumbnailSmallUrl`; dialogue player scene image remains sharp.
