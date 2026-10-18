# Quick Access v3 validation

The stack uses newest-first membership and bottom-up, placement-edge-aligned frames from `OctoshotCore/QuickAccessLayout.swift`. Expanded image edges have a 12-point resting gap. Expanded hover opens space for the capsule or bubble ring using the card spring, without resizing the panel. Both layouts reserve their maximum hover extent up front. The badge follows the top-most card rather than the reserved canvas. Collapsed depth is capped at four visible layers, with an 8-point upward step and a 2.5% scale reduction per layer. Back cards aspect-fit behind the front card; expansion restores each card's full dimensions. Collapsed hover never moves the cards; the canvas reserves toolbar padding, and bubbles draw over the peeking back cards.

Expansion reserves the union of both layouts before starting the card springs. Collapse keeps that reservation for one second, including the 30 ms per-card delays, then shrinks the panel. Reversing the transition cancels the pending shrink. Both corner and sidebar placements keep a bottom anchor on the capture-selected display; overflow scrolls with the newest card at the bottom. Reduce Motion skips the springs and delays.

## Build and tests

On a machine with the MLX Metal toolchain:

```sh
xcodegen generate
xcodebuild -scheme Octoshot -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath ./build-qa CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme OctoshotCoreTests -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath ./build-qa CODE_SIGNING_ALLOWED=NO test
```

Without that toolchain, use the existing CI stub generator, `bash Scripts/ci-xcodegen.sh`, instead. Add `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG` to the build command to retain the Debug snapshot entrypoint: the CI xcconfig otherwise replaces the Debug compilation conditions. The generator overwrites `Config/EmbeddedAI.xcconfig` with the CI stub; restore its original contents before committing a UI-only change.

## Offscreen snapshots only

```sh
OCTOSHOT_QA_SNAPSHOT_DIR=/tmp/octoshot-qa-v3 \
  ./build-qa/Build/Products/Debug/Octoshot.app/Contents/MacOS/Octoshot
```

The Debug entrypoint checks this variable **before** initializing the SwiftUI application or its delegate. It renders synthetic WIDE, TALL, and 3:2 images with `ImageRenderer` and exits without entering the normal app lifecycle. It does not capture a screen or request capture permissions. Native drag and scrolling overlays are omitted from this rendering path; card images, geometry, chrome, and toolbar views are shared with the live panel.

All renders have the same 392 × 620 point gradient canvas at 2× scale:

- `v3-collapsed.png` and `v3-expanded.png`
- `v3-toolbar-A.png` and `v3-toolbar-B.png`, with the middle TALL card hovered
- `v3-toolbar-A-collapsed.png` and `v3-toolbar-B-collapsed.png`, with the front card hovered
- `v3-expand-frames/frame-000.png` through `frame-023.png`, sampled from the layout with deterministic spring-like easing and a per-card stagger

The snapshot hover/time environment values exist only in Debug builds. Layout tests cover heterogeneous aspect ratios, placement edges, bottom-up order, exact gaps, layer caps, content bounds, interpolation endpoints and bounds, narrow-image capsule placement, and symmetric bubble positions outside the image.

Live drag, outside-click, hover, and multi-display interaction still require separate interactive verification; offscreen PNGs do not prove those event paths.
