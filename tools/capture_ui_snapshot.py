"""Filter blank simulator frames; UI tests and human review verify the app."""
import argparse
import struct
import subprocess
import tempfile
import time
from pathlib import Path


def has_nonblank_content(bmp: Path) -> bool:
    data = bmp.read_bytes()
    if data[:2] != b"BM":
        raise ValueError("Expected a BMP preview")
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bits = struct.unpack_from("<H", data, 28)[0]
    if width <= 0 or height == 0 or bits not in (24, 32):
        raise ValueError("Unsupported BMP preview")
    height = abs(height)
    stride = ((width * bits + 31) // 32) * 4
    samples = bright = dark = 0
    # Exclude system status and home-indicator areas. A launch screen contains
    # those elements but still has a completely empty app body.
    for y in range(int(height * .16), int(height * .84)):
        for x in range(int(width * .08), int(width * .92)):
            p = offset + y * stride + x * (bits // 8)
            rgb = data[p:p + 3]
            if len(rgb) != 3:
                raise ValueError("Truncated BMP preview")
            bright += min(rgb) >= 245
            dark += max(rgb) <= 12
            samples += 1
    return samples > 0 and max(bright, dark) / samples < .985


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("device")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + 45
    with tempfile.TemporaryDirectory(prefix="whale-frame-") as folder:
        preview = Path(folder) / "preview.bmp"
        while True:
            subprocess.run(["xcrun", "simctl", "io", args.device, "screenshot", str(args.output)], check=True)
            subprocess.run(["sips", "-Z", "200", "-s", "format", "bmp", str(args.output), "--out", str(preview)],
                           check=True, stdout=subprocess.DEVNULL)
            if has_nonblank_content(preview):
                print("Captured nonblank frame:", args.output.name, flush=True)
                return
            if time.monotonic() >= deadline:
                raise SystemExit("Screenshot remained blank: " + args.output.name)
            print("Waiting for nonblank frame:", args.output.name, flush=True)
            time.sleep(3)


if __name__ == "__main__":
    main()
