#!/usr/bin/env python3
"""Pack PNG iconset representations into an ICNS file using only the standard library."""
from pathlib import Path
import struct
import sys

iconset, output = map(Path, sys.argv[1:])
representations = {
    b"icp4": ("icon_16x16.png", 16),
    b"ic11": ("icon_16x16@2x.png", 32),
    b"icp5": ("icon_32x32.png", 32),
    b"ic12": ("icon_32x32@2x.png", 64),
    b"ic07": ("icon_128x128.png", 128),
    b"ic13": ("icon_128x128@2x.png", 256),
    b"ic08": ("icon_256x256.png", 256),
    b"ic14": ("icon_256x256@2x.png", 512),
    b"ic09": ("icon_512x512.png", 512),
    b"ic10": ("icon_512x512@2x.png", 1024),
}
chunks = []
for kind, (filename, pixels) in representations.items():
    png = (iconset / filename).read_bytes()
    if png[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", png[16:24]) != (pixels, pixels):
        raise SystemExit(f"Invalid PNG dimensions: {filename}")
    chunks.append(struct.pack(">4sI", kind, len(png) + 8) + png)
toc = b"".join(chunk[:8] for chunk in chunks)
body = struct.pack(">4sI", b"TOC ", len(toc) + 8) + toc + b"".join(chunks)
output.write_bytes(struct.pack(">4sI", b"icns", len(body) + 8) + body)
