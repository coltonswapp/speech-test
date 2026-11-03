# PRD: Animated flower mascot (UIKit)

**Project:** Shizen iOS app (`~/speech-test`, branch `feat/tweaks`)
**Status:** First pass written, not yet compiled or run on device

## Goal
Add a cute animated flower character (pink 5-petal flower, red face, black eyes) that the app can drive at runtime. It needs to support eye direction, eye shape, small idle movement, and switching between expressions smoothly. The first home for it is **Settings → Playground**, where it can be tweaked live.

## Constraints
- **UIKit only.** The app has no SwiftUI.
- No third-party dependencies. Rive, Lottie, SVG and SwiftUI were considered; native Core Animation was chosen for runtime control.
- Match existing Playground conventions: `ExperimentPalette`, `ExperimentSliderRow`, pushed from `SettingsViewController`.
- iOS 26 target. Default actor isolation is MainActor.
- New files under `shizen/` are picked up automatically (synchronized Xcode groups), so no pbxproj edits.

## Design
Every expression is a value for each of 14 knobs: `lookX`, `lookY`, `openness`, `lid`, `lidTilt`, `sclera`, `eyeSize`, `smile`, `wink`, `browTilt`, `tilt`, `peek`, `sparks`, `question`.

`MascotView` springs each knob toward its target independently, so any expression can blend into any other mid-flight. Idle sway, petal breathing and random blinks run on top.

Presets (17): Neutral, Happy, Excited, Curious, Thinking, Surprised, Focused, Skeptical, Confused, Pleased, Calm, Determined, Sleepy, Wink, Looking Left, Looking Right, Peek.

## What's built (`shizen/Experiments/`)
- `MascotExpression.swift`: `MascotParam` knobs, `MascotExpression` value type (with `swiftSnippet` export), `MascotPreset` presets.
- `MascotView.swift`: `UIView` built from `CAShapeLayer`s with a `CADisplayLink` spring driver.
  - API: `set(_:animated:)`, `set(_:to:)`, `look(at:)`.
  - Tunables: `stiffness`, `dampingRatio`, `idleMotionEnabled`, `autoBlinkEnabled`.
- `MascotPlaygroundViewController.swift`: Playground screen.
  - Preview pinned at top; preset chips, one slider per knob, spring sliders and toggles scroll below.
  - Touch-drag makes the eyes follow the finger.
  - Reset in the nav bar, plus a copy-as-Swift button.
- `Settings/SettingsViewController.swift`: new `.mascot` row in Playground (6 small insertions). The file already had unrelated uncommitted changes; leave them alone.

## Verification so far
- Geometry prototyped in Python and rendered for all 17 presets; closely matches the design sheet.
- Brace balance checked.
- **Not compiled.** No Swift toolchain was available where it was written.

## Next steps
1. Build in Xcode and fix compile errors.
2. Run on device; tune spring defaults (stiffness 220, damping ratio 0.62), blink timing and idle amounts.
3. Check expression transitions. Eye-to-arc is a crossfade plus squash, not a true path morph.
4. Compare Peek, Question and Sparks to the design sheet; spark angles and question-mark position are approximate.
5. Decide where the mascot lives in the real app (hosting view, screens, event-to-preset mapping).

## Out of scope
Sound, lip-sync with TTS, designer-authored animation pipeline (Rive), per-petal choreography.
