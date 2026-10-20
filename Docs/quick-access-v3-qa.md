# Quick Access v3 validation

The stack uses newest-first membership and bottom-up, placement-edge-aligned frames from `OctoshotCore/QuickAccessLayout.swift`. Expanded image edges have a 12-point resting gap. The badge follows the top-most card, 32 points above its top edge, not the ring. Collapsed depth is capped at four visible layers, with an 8-point upward step and a 2.5% scale reduction per layer. Back cards aspect-fit behind the front card; expansion restores each card's full dimensions. Collapsed hover never moves the cards; only the front card exposes actions.

Style A (**Below image**) remains the default: a 196 × 36-point capsule, 6 points below the image, aligned to the placement edge. Expanded hover shifts the hovered card and older cards upward by 42 points, opening a gap for the capsule using the card spring. Its maximum hover extent is reserved up front, so hover does not resize the panel.

Style B (**Ring** / **环形**) still persists as `bubbles`. It is a true-circle, semi-transparent overlay centered on the hovered card, drawn above the cards (and header), with no separate button bubbles. Its desired diameter is `min(max(imageWidth, imageHeight), 170)` points. The radius shrinks to fit the visible viewport inset by 10 points, without moving the center, and is clamped to zero if necessary. The inner radius is `max(outerRadius - 36, outerRadius * 0.3)`: nominal thickness is 36 points, reduced on small rings. The annulus uses ultra-thin material at 0.72 opacity; its center is unfilled. B reserves **no additional space**: collapsed/expanded hover frames equal no-hover frames, content size equals the base layout, and presentation frames equal the base interpolation. Hover opens no gaps and causes no panel growth; the ring can overlay neighboring cards.

Six equal 60-degree slots run clockwise from the top: Copy, Save, Annotate, Pin, OCR, Close. Each button has a localized tooltip and accessibility label; separators mark slot boundaries. Drawing, annular hit regions, and angle-based hover highlighting share `QuickAccessRingGeometry`. The center and empty outer corners are not action targets, though hovering the image retains the toolbar. B springs from scale 0.94/opacity 0 to scale 1/opacity 1 (response 0.34, damping 0.8); Reduce Motion disables the spring and scale change. Hidden actions disable hit testing and are hidden from accessibility.

Stack expansion (distinct from hover) reserves the union of collapsed and expanded sizes before starting the card springs. Collapse keeps that reservation for one second, including the 30 ms per-card delays, then shrinks the panel. Reversing the transition cancels the pending shrink. Both corner and sidebar placements keep a bottom anchor on the capture-selected display; overflow scrolls with the newest card at the bottom. Reduce Motion skips the springs and delays.

## Build and tests

On a machine with the MLX Metal toolchain:

```sh
xcodegen generate
xcodebuild -scheme Octoshot -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath ./build-qa CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme OctoshotCoreTests -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath ./build-qa CODE_SIGNING_ALLOWED=NO test
```

Without that toolchain, generate and build with the CI stub instead:

```sh
bash Scripts/ci-xcodegen.sh
xcodebuild -scheme Octoshot -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath ./build-qa CODE_SIGNING_ALLOWED=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG build
```

The explicit `DEBUG` retains the snapshot entrypoint: the CI xcconfig otherwise replaces the Debug compilation conditions. The generator overwrites `Config/EmbeddedAI.xcconfig`; preserve and restore its original contents after validation.

## Offscreen snapshots only

```sh
OCTOSHOT_QA_SNAPSHOT_DIR=/tmp/octoshot-qa-v5 \
  ./build-qa/Build/Products/Debug/Octoshot.app/Contents/MacOS/Octoshot
```

The Debug entrypoint checks this variable **before** initializing the SwiftUI application or its delegate. It renders synthetic WIDE, TALL, and 3:2 images with `ImageRenderer` and exits without entering the normal app lifecycle. It does not capture a screen or request capture permissions. Native drag and scrolling overlays are omitted from this rendering path; card images, geometry, chrome, and toolbar views are shared with the live panel.

The harness writes the following files on a gradient canvas at 2× scale. All v3 images and expand frames use 392 × 620 points (784 × 1240 pixels); v4 and v5 images use 392 × 700 points (784 × 1400 pixels):

- `v3-collapsed.png` and `v3-expanded.png`
- `v3-toolbar-A.png` and `v3-toolbar-B.png`, with the middle TALL card hovered
- `v3-toolbar-A-collapsed.png` and `v3-toolbar-B-collapsed.png`, with the front card hovered
- `v3-expand-frames/frame-000.png` through `frame-023.png`, sampled from the layout with deterministic spring-like easing and a per-card stagger
- `v4-toolbar-A.png` and `v4-toolbar-B.png`, expanded with the middle TALL card hovered
- `v4-toolbar-B-collapsed.png`, collapsed with the front WIDE card hovered
- `v5-toolbar-B.png`, expanded with the middle TALL card hovered
- `v5-toolbar-B-collapsed.png`, collapsed with the front WIDE card hovered

All versioned names render the current implementation; files at those paths in the chosen directory are overwritten. Other directories are untouched. Expand frames use style A without hover.

The snapshot hover/progress environment state exists only in Debug builds. `QuickAccessV3LayoutTests` covers A's 42-point gap opening and reservation bounds; B's zero reservation and unchanged hover/presentation layouts across placements and progress samples; collapsed hover invariance, heterogeneous aspect ratios, edge alignment, bottom-up order, 12-point gaps, depth/scale caps, empty/content sizes, interpolation bounds and fixed front bottom; narrow-card capsule fit and persisted raw values; circular centered rings, the 170-point cap, nominal 36-point thickness, six equal slots, centered shrinking to bounds, shrunk-ring hover outside a short card, segment/seam mapping, and center/empty-corner/outside/nonfinite hit rejection.

Live drag, outside-click, hover, and multi-display interaction still require separate interactive verification; offscreen PNGs do not prove those event paths.
