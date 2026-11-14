# Main top tab bar: agent replication spec

Give this file to another coding agent. It describes the Shizen home-screen top tab bar: a horizontally scrolling row of text tabs with a liquid-glass pill, synced to a paging scroll view, with **no divider** between the navigation bar and the tab bar. Reproduce the **look, layering and behavior**, not a line-for-line port.

**Platform:** UIKit, **iOS 26+** (`UIGlassEffect`, `topEdgeEffect`, `UIScrollEdgeElementContainerInteraction`). Fallbacks for older OS are noted but untested.

Source of truth in the Shizen repo (for reference only):
- `shizen/UI/GameCategoryTabBar.swift` (the bar)
- `shizen/App/MainViewController.swift` (host + pager)
- `shizen/App/MainTabScrollable.swift` (inset protocol)
- `InteractionKit/Sources/InteractionKit/LiquidGlassEffectView.swift` (glass)
- `shizen/App/SceneDelegate.swift:24` (plain `UINavigationController`)

> Honesty note: Shizen has **no explicit divider-removal code**. The clean look comes from (a) iOS 26's nav bar, (b) *not* customizing the nav bar, and (c) the layout below. Do not "fix" it by adding appearance code unless you see a line (see section 5).

---

## 1. What it is

- A **top** bar, not a `UITabBar`. 44 pt tall, transparent, pinned under the nav bar.
- Tabs are text labels in a horizontal `UICollectionView`. The selected tab is always **centered**.
- One **glass capsule** sits behind the labels at the bar's center. It resizes smoothly to the selected tab's width while swiping.
- Pages live in a full-screen horizontal paging `UIScrollView`. Bar and pager stay in sync in both directions.
- Unselected tabs fade out when the user scrolls the page down, and come back on scroll-up or any horizontal interaction.

## 2. Layering and view hierarchy

```
UINavigationController (plain, no appearance customization)
└─ HostViewController.view          (background = a palette color, not pure white/black)
   ├─ pagingScrollView              pinned to view.topAnchor / leading / trailing / bottom
   │   └─ pagesStackView (horizontal)  one container per page, width == pager frame width
   │       └─ child VC view            vertical scroll view with top inset (see §4)
   └─ tabBar (GameCategoryTabBar)   ABOVE the pager; top = safeAreaLayoutGuide.top, height 44
       ├─ pillGlass (UIVisualEffectView)   BEHIND labels, non-interactive
       └─ collectionView (clear)           tab labels
```

Order matters: **pager first, tab bar second (bringSubviewToFront)**. Inside the bar: **pill glass first, collection view second**, so labels draw over the glass.

## 3. Glass recipe

This is the look. Use it verbatim.

```swift
public enum LiquidGlassEffectView {

    public static func makeContainer() -> UIVisualEffectView {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true          // native touch-lift behavior
            return UIVisualEffectView(effect: glassEffect)
        } else {
            return UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        }
    }

    public static func applyCapsuleStyle(to view: UIVisualEffectView, cornerRadius: CGFloat = 40) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor

        // Capsule keeps a soft drop shadow, so it must NOT clip.
        view.clipsToBounds = false
        view.layer.masksToBounds = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 12
        view.layer.shadowOpacity = 0.3

        if #available(iOS 26.0, *) {
            view.cornerConfiguration = .corners(radius: .fixed(cornerRadius))
        } else {
            view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.82)
        }
    }
}
```

Rules that make it look good:

1. **Real `UIGlassEffect(style: .regular)`**, `isInteractive = true`. No manual blur or tint.
2. **1 pt hairline `white @ 0.22`**, `.continuous` corner curve, plus `cornerConfiguration = .corners(radius: .fixed(r))` on iOS 26 (in addition to `layer.cornerRadius`).
3. **Soft black drop shadow**: offset (0, 4), radius 12, opacity 0.3. `clipsToBounds = false`.
4. **The glass is empty.** Labels are siblings above it, never subviews. `isUserInteractionEnabled = false` so touches reach the collection view.
5. **No tint.** Color comes from whatever scrolls behind it.
6. **Content scrolls under the bar** so the glass has something to refract (see §4). Give the host view a palette background rather than pure white/black.
7. **Resize the pill by `bounds` and `center`, not Auto Layout.** It is frame-driven so it can track scroll progress every frame. Set `cornerRadius = height / 2` each update.
8. Label color blends `.secondaryLabel` → `.label` and weight regular → bold by *selectedness* (below), which keeps text legible on glass in light and dark.

## 4. Layout: how it's placed on the host view controller

### 4.1 Bar placement

```swift
view.addSubview(tabBar)
view.bringSubviewToFront(tabBar)
NSLayoutConstraint.activate([
    tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
    tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
    tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
])
// The bar sets its own height: heightAnchor == 44 (GameCategoryTabBar.layoutHeight)
```

No gap between the nav bar and the tab bar. The bar has **no background, border or separator view**.

### 4.2 Pager

```swift
pagingScrollView.translatesAutoresizingMaskIntoConstraints = false
pagingScrollView.backgroundColor = .clear
pagingScrollView.topEdgeEffect.style = .soft
pagingScrollView.topEdgeEffect.isHidden = false
pagingScrollView.delaysContentTouches = false
view.addSubview(pagingScrollView)

// Pinned to view.topAnchor, NOT the safe area: content runs under both bars.
pagingScrollView.topAnchor.constraint(equalTo: view.topAnchor)
pagingScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
pagingScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
pagingScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)

// Stack view inside, using the content/frame layout guides:
pagesStackView.top/leading/trailing/bottom == pagingScrollView.contentLayoutGuide
pagesStackView.heightAnchor == pagingScrollView.frameLayoutGuide.heightAnchor
// Each page container: widthAnchor == pagingScrollView.frameLayoutGuide.widthAnchor
```

The pager subclass claims the pan only when the swipe is clearly horizontal, so nested vertical scroll views keep working:

```swift
final class HorizontalPagingScrollView: UIScrollView {
    private func commonInit() {
        isPagingEnabled = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceVertical = false
        alwaysBounceHorizontal = true
        bounces = true
        contentInsetAdjustmentBehavior = .never
    }
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer, pan === panGestureRecognizer
        else { return super.gestureRecognizerShouldBegin(g) }
        let t = pan.translation(in: self)
        return abs(t.x) > abs(t.y)
    }
}
```

### 4.3 Making page content clear the bars (manual inset)

Each page exposes its vertical scroll views; the host applies the inset **itself**.

```swift
protocol MainTabScrollable: UIViewController {
    var mainTabScrollViews: [UIScrollView] { get }
}

extension UIScrollView {
    func applyMainTabTopInset(_ topInset: CGFloat) {
        guard abs(contentInset.top - topInset) >= 0.5 else { return }
        contentInsetAdjustmentBehavior = .never          // we own the inset; don't double count
        let wasShowingTop = contentOffset.y <= -contentInset.top + 1
        var inset = contentInset;  inset.top = topInset;  contentInset = inset
        var ind = verticalScrollIndicatorInsets;  ind.top = topInset
        verticalScrollIndicatorInsets = ind
        if wasShowingTop { contentOffset.y = -topInset }  // keep resting at the top
    }
}
```

Host, in `viewDidLayoutSubviews`:

```swift
let safeTop = view.safeAreaInsets.top
guard safeTop > 0 else { return }
let topInset = safeTop + GameCategoryTabBar.layoutHeight   // 44
guard abs(topInset - lastAppliedTopInset) >= 0.5 else { return }
lastAppliedTopInset = topInset
for child in pageViewControllers {
    (child as? MainTabScrollable)?.mainTabScrollViews.forEach { $0.applyMainTabTopInset(topInset) }
}
```

Every vertical scroll view on every page also gets:

```swift
scrollView.topEdgeEffect.style = .soft
scrollView.topEdgeEffect.isHidden = false
scrollView.delaysContentTouches = false
```

## 5. No divider between nav bar and tab bar (read this carefully)

**Why there is no line:**

1. **Deployment target iOS 26.0.** The iOS 26 nav bar has no hairline; its backdrop is the soft scroll-edge effect.
2. **Plain `UINavigationController`, zero appearance customization.** No `UINavigationBar.appearance()`, no `standardAppearance` / `scrollEdgeAppearance` on the host, no `shadowColor`, `shadowImage`, `isTranslucent`, or hidden bar. Do **not** add an opaque `standardAppearance`; that brings back a background and separator.
3. **Host sets only** `title`, `navigationItem.largeTitleDisplayMode = .never`, and two bar button items. The tab bar is a normal subview, **not** a nav-bar accessory or title view.
4. **Tab bar is transparent and flush** against the nav bar's safe-area bottom (`safeAreaLayoutGuide.topAnchor`, no gap, no background/separator).
5. **Content is full-bleed behind both bars.** Pager is pinned to `view.topAnchor`; `contentInsetAdjustmentBehavior = .never` on the pager and on every page scroll view; the `safeTop + 44` inset is applied manually (§4.3). With content under both bars there is no edge for a divider to sit on.
6. **One soft top-edge effect covers both bars.** `topEdgeEffect.style = .soft`, `isHidden = false` everywhere, plus a `UIScrollEdgeElementContainerInteraction` on the tab bar so the system treats it as part of the top chrome:

   ```swift
   // In the bar:
   private let scrollEdgeInteraction: UIScrollEdgeElementContainerInteraction = {
       let i = UIScrollEdgeElementContainerInteraction()
       i.edge = .top
       return i
   }()
   // in init: addInteraction(scrollEdgeInteraction)

   func setScrollEdgeScrollView(_ scrollView: UIScrollView?) {
       scrollEdgeInteraction.scrollView = scrollView
   }
   ```

   The host **must re-point it whenever the active page changes** (on initial layout and from `scrollViewDidScroll` when the nearest page index changes):

   ```swift
   tabBar.setScrollEdgeScrollView(verticalScrollView(forPageAt: activePageIndex))
   ```

   A stale or nil scroll view here is a likely cause of a stray line or a missing fade after swiping.
7. **No `setContentScrollView` call.** The pager is horizontal, and nothing registers a content scroll view for the nav bar. We believe this keeps the nav bar in its transparent scroll-edge state rather than flipping to a standard state with a separator. (Inferred from the absence of the call; not tested in isolation.)

**If you still see a line, check in this order:**

1. An opaque `standardAppearance` / `UINavigationBar.appearance()` somewhere.
2. The scroll-edge interaction pointing at nil or at an off-screen page.
3. A page scroll view still on the default `contentInsetAdjustmentBehavior` (UIKit adds the inset on top of yours).
4. An app targeting below iOS 26.

**Defensive override** (not used in Shizen on the main screen, untested here). Apply per screen so it does not leak to pushed screens:

```swift
let a = UINavigationBarAppearance()
a.configureWithTransparentBackground()
a.shadowColor = .clear
navigationItem.standardAppearance = a
navigationItem.scrollEdgeAppearance = a
navigationItem.compactAppearance = a
navigationItem.compactScrollEdgeAppearance = a
```

Shizen's pushed screen `LessonScenarioPickerViewController` does set a transparent appearance like this because it has its own scrolling content. The main screen does not.

## 6. The tab bar internals

### 6.1 Constants and subviews

```swift
static let layoutHeight: CGFloat = 44
private static let pillHeight: CGFloat = 36
private static let snapAnimationDuration: TimeInterval = 0.22
private static let snapDecelerationRate = UIScrollView.DecelerationRate(rawValue: 0.92)
```

- `pillGlass = LiquidGlassEffectView.makeContainer()`, `isUserInteractionEnabled = false`, `applyCapsuleStyle(cornerRadius: pillHeight / 2)`.
- `collectionView`: horizontal flow layout, `minimumInteritemSpacing = 8`, `backgroundColor = .clear`, hidden indicator, `decelerationRate = 0.92`, pinned to all four edges of the bar. Bar height constraint is 44.
- Add `pillGlass` first, then `collectionView`.

### 6.2 Cell sizing and centering

- Cell size: `width = boldTextWidth(title, 14pt bold) + badgeWidth + 32`, `height = 36`.
- Section insets: `top 4, bottom 4`, `left = bounds.width/2 - firstCellWidth/2`, `right = bounds.width/2 - lastCellWidth/2`. This is why every tab, including the first and last, can sit centered.
- Center of item *i* in content coordinates = `leftInset + Σ(widths[0..<i]) + 8*i + widths[i]/2`. For fractional progress, linearly interpolate between neighbor centers. Target offset = `center - collectionView.width/2`, clamped to `[0, contentWidth - width]`.

### 6.3 Progress model (the core)

Everything is driven by a single `progress: CGFloat` in `0...(count-1)`: the pager offset divided by pager width.

```swift
private func updatePillAndLabels(progress: CGFloat) {
    let count = titles.count
    let clamped = max(0, min(progress, CGFloat(count - 1)))
    let widths = itemWidths()
    let i = min(Int(clamped), count - 1)
    let t = clamped - CGFloat(i)
    let pillWidth = (i >= count - 1 || t <= 0) ? widths[i]
                                                : widths[i] + t * (widths[i + 1] - widths[i])
    pillGlass.bounds = CGRect(x: 0, y: 0, width: pillWidth, height: Self.pillHeight)
    pillGlass.center = CGPoint(x: bounds.midX, y: bounds.midY)   // pill never moves; labels scroll under it
    pillGlass.layer.cornerRadius = Self.pillHeight / 2
    for cell in collectionView.visibleCells {
        guard let tab = cell as? TabCell, let ip = collectionView.indexPath(for: cell) else { continue }
        tab.setSelectedness(max(0, min(1, 1 - abs(CGFloat(ip.item) - clamped))))
    }
    applyInactiveTabVisibility()
}
```

Cell label styling by `selectedness` in `0...1`:

```swift
titleLabel.textColor = blend(.secondaryLabel → .label, t)
titleLabel.font = .systemFont(ofSize: 14, weight: .regular → .bold by t)  // interpolate weight rawValue
```

### 6.4 Sync, both directions

Bar protocol:

```swift
protocol GameCategoryTabBarDelegate: AnyObject {
    func tabBar(_ tabBar: GameCategoryTabBar, didSelectTabAt index: Int)
    func tabBar(_ tabBar: GameCategoryTabBar, didScrollToPageProgress progress: CGFloat)
    func tabBarDidEndScrolling(_ tabBar: GameCategoryTabBar)
}
```

- **Tap a tab** → bar centers it (animated, 0.22 s ease-out) and calls `didSelectTabAt`. The host does:
  ```swift
  isUpdatingFromScroll = true
  CATransaction.begin()
  CATransaction.setAnimationDuration(0.22)
  CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
  pagingScrollView.setContentOffset(CGPoint(x: width * CGFloat(index), y: 0), animated: true)
  CATransaction.commit()
  ```
- **Scrub the bar** (drag its collection view) → `didScrollToPageProgress`; host sets `pagingScrollView.contentOffset.x = progress * width` with `isUpdatingFromScroll = true`.
- **Swipe the pager** → in `scrollViewDidScroll`, if `!isUpdatingFromScroll`: `tabBar.setPageProgress(offset / width, animated: false)`.
- **Loop guard:** `isUpdatingFromScroll` (host) and `isProgrammaticScroll` / `suspendSelectionSyncFromScroll` (bar). Clear them in `scrollViewDidEndScrollingAnimation`, `scrollViewDidEndDecelerating`, and `scrollViewDidEndDragging(willDecelerate: false)`, and call `tabBarDidEndScrolling`.
- **Snap:** in `scrollViewWillEndDragging` on the bar's collection view, rewrite `targetContentOffset.x` to the nearest tab center and set `selectedIndex`.
- **Initial offset:** on first layout with `pager.bounds.width > 0`, set `contentOffset.x = width * defaultIndex` and call `tabBar.syncScrollPositionToSelection(animated: false)`. Also re-sync the bar in its own `layoutSubviews` when not in hold mode.
- **Haptics:** soft `UIImpactFeedbackGenerator` when the nearest page index changes mid-swipe; light impact on tab tap.

### 6.5 Collapse on vertical scroll

Host observes `contentOffset` of the active page's scroll view (KVO):

```swift
let offsetY = scrollView.contentOffset.y
let scrollPosition = offsetY + scrollView.adjustedContentInset.top
defer { lastObservedVerticalOffset = offsetY }

if scrollPosition <= 12 { tabBar.setShowsInactiveTabs(true, animated: true); return }
let delta = offsetY - lastObservedVerticalOffset
guard abs(delta) >= 2 else { return }
if delta > 0 {
    tabBar.setShowsInactiveTabs(false, animated: true)
} else if hasScrolledUpFromBottomEdge(in: scrollView) {      // > 48 pt above bottom; ignore bounce
    tabBar.setShowsInactiveTabs(true, animated: true)
}
```

Also expand on `scrollViewWillBeginDragging` of the pager and on any horizontal interaction.

Bar side:

```swift
func setShowsInactiveTabs(_ shows: Bool, animated: Bool) {
    guard showsInactiveTabs != shows else { return }
    showsInactiveTabs = shows
    collectionView.isScrollEnabled = shows
    UIView.animate(withDuration: 0.32, delay: 0,
                   options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
        self.applyInactiveTabVisibility()
    }
    if !shows { setPageProgress(CGFloat(selectedIndex), animated: animated) }
}

private func applyInactiveTabVisibility() {
    for cell in collectionView.visibleCells {
        guard let ip = collectionView.indexPath(for: cell) else { continue }
        let isActive = ip.item == selectedIndex
        cell.alpha = isActive ? 1 : (showsInactiveTabs ? 1 : 0)
        cell.isUserInteractionEnabled = showsInactiveTabs || isActive
    }
}
```

### 6.6 Optional: long-press scrub (Shizen-specific, safe to omit)

A 0.42 s long press (movement allowance 14 pt) swaps the labels for "hold options"; sliding sideways steps 56 pt per option; release commits. Used for the lesson-track picker with a badge on the first tab. Skip unless you need it.

## 7. Implementation order

1. Add `LiquidGlassEffectView` (§3).
2. Build `GameCategoryTabBar` (§6): collection view, pill, centering math, progress model.
3. Build the pager and `MainTabScrollable` inset (§4).
4. Wire the host and delegate (§6.4), then the scroll-edge interaction (§5.6) and collapse (§6.5).
5. Verify no divider (§5), specifically: plain nav controller, nothing set on `navigationItem` appearance, every scroll view on `.never` with the manual inset, and `setScrollEdgeScrollView` updated on page change.

## 8. Pitfalls

- Pill in Auto Layout → jitter during swipes. Keep it frame-driven.
- Glass `clipsToBounds = true` → the shadow disappears.
- Labels inside the glass view → muddied material. Keep them siblings.
- Pager pinned to the safe area → content no longer scrolls under the bars, so the glass has nothing to refract and an edge appears.
- Leaving `contentInsetAdjustmentBehavior` at the default → double top inset.
- Forgetting to re-point the scroll-edge interaction after a page change.
- Opaque nav bar appearance → separator returns.
