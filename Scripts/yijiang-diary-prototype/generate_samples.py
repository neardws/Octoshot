#!/usr/bin/env python3
"""Synthetic Yijiang Diary prototype frames (no personal data)."""
from __future__ import annotations

import json
import struct
import zlib
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SAMPLES = ROOT / "samples"

SCENES = [
    ("Xcode", "struct YijiangDiaryEntry {\n    let timestamp: Date\n}"),
    ("Xcode", "func runPrototype() async throws {\n    // keyframe selection\n}"),
    ("Safari", "Octoshot — privacy-first screenshots"),
    ("Safari", "Computer History documentation"),
    ("Notes", "一酱日记 M0 原型评测清单"),
]


def png_rgb(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    r, g, b = rgb
    raw = b"".join(bytes([r, g, b, 255]) * width for _ in range(height))
    compressor = zlib.compress(raw, level=9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressor) + chunk(b"IEND", b"")


def main() -> None:
    SAMPLES.mkdir(parents=True, exist_ok=True)
    base = datetime(2025, 10, 17, 9, 0, 0, tzinfo=timezone(timedelta(hours=8)))
    colors = [(32, 44, 58), (40, 52, 70), (28, 110, 87), (88, 52, 120), (120, 72, 40)]
    for index, (app, text) in enumerate(SCENES):
        ts = base + timedelta(minutes=index * 4, seconds=index * 7)
        stamp = ts.strftime("%Y-%m-%dT%H-%M-%S%z")
        stamp = stamp[:-2] + ":" + stamp[-2:]  # +08:00 style for filename
        stem = f"{stamp}_{app}"
        png_path = SAMPLES / f"{stem}.png"
        meta_path = SAMPLES / f"{stem}.meta.json"
        png_path.write_bytes(png_rgb(320, 180, colors[index % len(colors)]))
        meta = {
            "timestamp": ts.isoformat(),
            "frontmostApp": app,
            "accessibilityText": text,
        }
        meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(SCENES)} frames to {SAMPLES}")


if __name__ == "__main__":
    main()
