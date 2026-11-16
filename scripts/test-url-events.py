#!/usr/bin/env python3
"""Exercise actual cold/warm Launch Services URL delivery, without opening Chrome."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def wait_for_receipt(receipts: Path, key: str, value: str) -> None:
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if receipts.exists():
            # Wait for complete JSONL records; the app may be appending the next record.
            lines = receipts.read_text().splitlines(keepends=True)
            seen = [json.loads(line) for line in lines if line.endswith("\n")]
            if any(item.get(key) == value for item in seen):
                return
        time.sleep(0.2)
    raise AssertionError(f"macOS did not deliver {key}={value}; receipts: "
                         f"{receipts.read_text() if receipts.exists() else '(none)'}")


def main() -> None:
    app = Path(sys.argv[1] if len(sys.argv) > 1 else "dist/Profile Router.app").resolve()
    with tempfile.TemporaryDirectory(prefix="profile-router-url-events-") as directory:
        receipts = Path(directory) / "url-receipts.jsonl"
        subprocess.run(["/usr/bin/open", "-n", "-a", str(app),
                        "https://cold-start.example.invalid/", "--args",
                        "--url-receipt-smoke-test", str(receipts)], check=True)
        wait_for_receipt(receipts, "host", "cold-start.example.invalid")
        subprocess.run(["/usr/bin/open", "-a", str(app),
                        "https://warm-start.example.invalid/"], check=True)
        wait_for_receipt(receipts, "host", "warm-start.example.invalid")
        html = Path(directory) / "a local report é.html"
        html.write_text("<!doctype html><title>Routing smoke test</title>")
        subprocess.run(["/usr/bin/open", "-a", str(app), str(html)], check=True)
        wait_for_receipt(receipts, "kind", "file")
        print("PASS: cold-start URL, running-app URL, and local HTML file events reached Profile Router.")


if __name__ == "__main__":
    main()
