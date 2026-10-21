# Offline annotated export benchmark

`Scripts/export-bench.sh /tmp/octoshot-export-old` builds a standalone Debug-only
target (not included in either shipping project), exports both render paths at
1920x1080 and 5120x2880, then writes median/p95 and raw samples to `bench.json`.
Set `ITERATIONS` to override 20. No GUI is launched and no capture APIs are used.
Fixtures use a fixed PRNG seed, bitmap glyph-like bars, gradients and checkerboard;
50 fixed annotations contain ten blur and ten pixelate regions separate from vectors.
The editor path is the actual `AnnotationCanvasView.currentImage()` composite.
Core coordinates are converted to its bottom-left convention.

Validation compares each redaction interior against the editor's unannotated
composite in a canonical RGBA format; failure exits nonzero before timings.
Missing Metal/GPU support can cause this failure in a sandbox. Run once outside
the sandbox rather than interpreting this as performance evidence.

Annotation timings are warm rebuilds, after fixture setup and validation; first
render and fixture generation are excluded. Save includes encoding and disk
write, not durable fsync. Baseline save is synchronous on the main actor so its
blocked time equals save wall time. In NEW, saves await ImageFormats' background
encoder/writer; `main-snapshot` measures synchronous CGImage extraction only,
not total main-thread blocked time (dispatch and completion overhead excluded).
NEW explicitly rebuilds the editor once per annotation sample, like OLD's
currentImage did, rather than timing the now-cached composite accessor.
PNG/JPEG output uses ImageFormats with JPEG
quality 0.85. Text rendering may vary across OS/font versions: compare on the same
machine and display scale. Keep OLD and NEW output directories separate.
