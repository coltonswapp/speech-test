# Underglow glass component — agent replication spec

Give this file to another coding agent. It is a complete recipe for the glass + colored underglow used on Shizen dialogue bubbles and lesson-path unit headers. Implement the **look and layering**, not a line-for-line port of app-specific types.

**Platform:** UIKit. Liquid glass (`UIGlassEffect`) requires **iOS 26**. Fall back to ultra-thin material blur on earlier OS versions. The underglow itself is Core Animation and works on older iOS.

**Do not** put the glow *inside* the glass view. The whole point is a speaker-tinted wash sitting **behind** translucent glass so the blur refracts it.

---

## 1. What it looks like

A rounded-rect liquid-glass plate (chat-bubble or header card) with:

- Continuous-corner glass, 1pt white hairline (`white @ 0.22`).
- **No drop shadow on the glass itself** (bubble/header style). Capsules/pills *do* use a black drop shadow; bubbles do not.
- A **soft colored elliptical blob** behind the glass, biased toward the **bottom edge**, slightly inset upward, never filling the whole silhouette.
- Glow opacity driven by “emphasis” (active / speaking / selected). At rest, glass stays visible; glow fades out.
- Same hue family as system colors (`systemYellow`, `systemBlue`, …). Karaoke / highlight fills reuse that hue at `0.55` alpha.

Default production look (tuned, not a guess):

| Parameter | Default |
|---|---|
| Vertical edge | bottom |
| Height ratio | `0.12` of bubble height |
| Width ratio | `1.0` of available width |
| Horizontal inset | `0` |
| Offset X | `0` |
| Offset Y | `-5.88` (up from the bottom edge) |
| Opacity | `0.39` |
| Glow corner radius | `36` |
| Blur radius | `14` |
| Color | `systemYellow` (or per-speaker tint) |
| Glass corner radius | `18` |

Compact variant (small meter pills): same as default, then `horizontalInset = 12`, `blurRadius = 8`, `offsetX = 0`. Use this when blur would otherwise bleed past a small silhouette.

---

## 2. Layer stack (z-order)

Host view: `clipsToBounds = false`. Glow must be allowed to bloom outside the glass.

```
[back]  glowView          — clear UIView, frames (not Auto Layout)
        └─ CAGradientLayer (.radial)
        └─ layer.shadow*  — same hue, extra bloom
        glassView         — UIVisualEffectView, Auto Layout pin to host edges
        content           — labels, etc. on top of glass
[front]
```

Critical:

1. Add glow **first**, glass **second**, content **third**.
2. Glow view uses **manual frames** in `layoutSubviews`. Auto Layout fights the blur padding.
3. Glass view **does** use Auto Layout, pinned to the host.
4. Glow and glass are `isUserInteractionEnabled = false`.
5. Glass uses `clipsToBounds = true` so the material stays in the rounded rect. The **host** and **glow** must not clip.

---

## 3. Glass chrome

### Create

```swift
if #available(iOS 26.0, *) {
    let glassEffect = UIGlassEffect(style: .regular)
    glassEffect.isInteractive = true   // bubbles / headers: true
                                       // static chips: false
    return UIVisualEffectView(effect: glassEffect)
} else {
    return UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
}
```

Light-surface chips (vocab/grammar pills on pale pages) use the same `UIGlassEffect` with `isInteractive = false`, and on older OS `systemUltraThinMaterialLight`.

### Style (bubble / header — no shadow)

```swift
view.translatesAutoresizingMaskIntoConstraints = false
view.layer.cornerRadius = cornerRadius          // 18 for bubbles
view.layer.cornerCurve = .continuous
view.layer.borderWidth = 1
view.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
view.clipsToBounds = true
view.layer.masksToBounds = true

if #available(iOS 26.0, *) {
    view.cornerConfiguration = .corners(radius: .fixed(cornerRadius))
} else {
    view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.82)
}
```

Do **not** set `showsShadow` / black drop shadow on bubble glass. The underglow is the only extra light.

Capsule/pill chrome (optional, not part of the bubble look): same rounding + hairline, plus `shadowOffset (0, 4)`, `shadowRadius 12`, `shadowOpacity 0.3`, `shadowColor black`, and `clipsToBounds = false` on that glass view.

---

## 4. Underglow configuration

```swift
struct UnderglowConfiguration {
    enum VerticalEdge { case top, center, bottom }

    var verticalEdge: VerticalEdge = .bottom
    var heightRatio: CGFloat = 0.12      // clamped 0...1
    var widthRatio: CGFloat = 1.0        // clamped 0...1
    var horizontalInset: CGFloat = 0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = -5.88
    var opacity: CGFloat = 0.39
    var cornerRadius: CGFloat = 36       // glow blob, not glass
    var blurRadius: CGFloat = 14
    var color: UIColor = .systemYellow
}
```

### Glow frame (core blob, before blur padding)

In host bounds `bubbleBounds`:

```
availableWidth = max(0, bubbleBounds.width - horizontalInset * 2)
glowWidth      = availableWidth * clamp(widthRatio, 0, 1)
glowHeight     = bubbleBounds.height * clamp(heightRatio, 0, 1)
centerX        = bubbleBounds.midX + offsetX

switch verticalEdge:
  top:    centerY = glowHeight / 2 + offsetY
  center: centerY = bubbleBounds.midY + offsetY
  bottom: centerY = bubbleBounds.height - glowHeight / 2 + offsetY

coreFrame = CGRect(
  x: centerX - glowWidth / 2,
  y: centerY - glowHeight / 2,
  width: glowWidth,
  height: glowHeight
)
```

### Layout with blur padding

```
padding     = blurRadius > 0 ? blurRadius * 0.75 : 0
glowView.frame = coreFrame.insetBy(dx: -padding, dy: -padding)   // expands
gradient.frame = glowView.bounds
gradient.cornerRadius = configuration.cornerRadius
gradient.cornerCurve = .continuous
```

If `blurRadius > 0`, set a `shadowPath` on `glowView.layer` to the **core** rect in glow-view coordinates (the inner rect inset by `padding`), rounded with `configuration.cornerRadius`. This keeps the extra bloom cheap and shaped.

If `coreFrame` is empty, zero both frames and clear `shadowPath`.

---

## 5. Underglow appearance

`CAGradientLayer` with `type = .radial`.

```
startPoint = (0.5, 0.5)
endPoint   = (1, 1)
```

**No blur (`blurRadius <= 0`):**

- `colors = [color, color]`
- `locations = [0, 1]`
- `shadowOpacity = 0`, `shadowPath = nil`

**With blur (production):**

```
midStop = clamp(0.55 - blurRadius / 80, 0.2, 0.8)

colors = [
  color.cgColor,
  color.withAlphaComponent(0.4).cgColor,
  UIColor.clear.cgColor,
]
locations = [0, midStop, 1]

shadowColor   = color
shadowRadius  = blurRadius
shadowOpacity = 0.5
shadowOffset  = .zero
```

With defaults (`blurRadius = 14`): `midStop ≈ 0.375`.

---

## 6. Emphasis (show / hide the glow)

Glass chrome stays up. Glow alpha is:

```
glowView.alpha = emphasis * configuration.opacity
glowView.isHidden = emphasis < 0.001
```

`emphasis` is `0...1` (speaking line, selected header, swipe-reveal, etc.). Combine independent drivers with `max(a, b)` if needed.

Do not hide the glass when emphasis is 0.

---

## 7. Minimal host (copy this)

```swift
final class UnderglowGlassView: UIView {
    private let glowView = UIView()
    private let gradient = CAGradientLayer()
    private let glassView: UIVisualEffectView
    var configuration = UnderglowConfiguration() {
        didSet { applyAppearance(); setNeedsLayout() }
    }
    var emphasis: CGFloat = 1 {
        didSet { applyEmphasis() }
    }
    private let glassCornerRadius: CGFloat = 18

    override init(frame: CGRect) {
        // glassView = makeContainer() as in §3
        super.init(frame: frame)
        clipsToBounds = false

        glowView.backgroundColor = .clear
        glowView.clipsToBounds = false
        glowView.isUserInteractionEnabled = false
        gradient.type = .radial
        glowView.layer.addSublayer(gradient)

        // applyBubbleStyle(glassView, cornerRadius: 18)
        glassView.isUserInteractionEnabled = false

        addSubview(glowView)
        addSubview(glassView)
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyAppearance()
        applyEmphasis()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutGlow()
    }
}
```

Fill `applyAppearance`, `layoutGlow`, and `applyEmphasis` from §4–§6.

Put labels / buttons **above** `glassView`. Do not put content in `glassView.contentView` unless you need the glass to clip it; Shizen keeps content as a sibling so furigana can overflow slightly.

---

## 8. Color language (optional)

Shizen maps speakers to system colors. Classic preset: **leading = blue**, **trailing = yellow**. Other named pairs (sunset, ocean, berry, forest, neon, soft, warm) are just two `UIColor.system*` values.

Token / karaoke wash on text: `color.withAlphaComponent(0.55)`.

If you also have a solid Messages-style fill mode, that is a **different** treatment (opaque fill + optional tail path). Do not mix a solid fill with the underglow. Glass mode hides the solid fill; solid mode hides glass and glow.

---

## 9. What will look wrong if you skip it

| Mistake | Result |
|---|---|
| Glow as a subview of the glass view | Glow clipped; no bloom through the material |
| Host `clipsToBounds = true` | Same — glow truncated at the rect |
| Auto Layout on the glow view | Blur padding fights constraints; jitter on resize |
| Black drop shadow on bubble glass | Muddy, “card” look instead of a light wash |
| Filling the full bounds with glow | Reads as a tinted plate, not a bottom ember |
| `heightRatio` near 1 | Same problem |
| Radial `endPoint` at `(0.5, 1)` | Stretched / off-center blob; use `(1, 1)` |
| Skipping `shadowPath` | Extra GPU cost; bloom shape mismatches the blob |
| Hiding glass when idle | Chrome pops in/out; only the glow should fade |
| `UIGlassEffect` without iOS 26 availability | Crash / compile failure — always gate it |
| Interactive glass on static chips | Unwanted specular response on scroll |

---

## 10. Acceptance checks

1. Idle (`emphasis = 0`): rounded glass plate visible, **no** colored bloom.
2. Active (`emphasis = 1`): soft colored band along the **bottom**, slightly above the edge, refracted by the glass. Not a hard rectangle.
3. Bloom extends a few points **outside** the glass, especially left/right of the bottom corners.
4. Changing `color` only retints the wash; geometry stays put.
5. Compact meter: tighter blur, 12pt side inset, no extra X offset.
6. Resize the host: glow stays a thin bottom band, not a stretched oval covering the card.
7. Pre-iOS 26: ultra-thin dark material + same underglow still reads as “glass over a light.”

Reference tuning UI in the original app: a debug screen with live sliders for every configuration field, plus “copy values.” You do not need that screen to ship; you need the defaults above.

---

## 11. Source files in Shizen (if you have the repo)

- Glass factory: `InteractionKit/Sources/InteractionKit/LiquidGlassEffectView.swift`
- Glow config + frame math: `shizen/Dialogue/DialogueBubbleUnderglowConfiguration.swift`
- Bubble host (canonical): `shizen/Dialogue/DialogueJapaneseBubbleView.swift` (`applyUnderglowAppearance`, `layoutUnderglow`, `applyEmphasisVisuals`)
- Same glow on path headers: `PathUnitHeaderView` in `shizen/Experiments/LanguageProgressSnakeExperimentViewController.swift`
- Live tuner: `shizen/Experiments/DialogueBubbleUnderglowExperimentViewController.swift`

Pills (`DialogueGlassPillView`) are **glass only** — no underglow. Do not copy that file for this effect.
