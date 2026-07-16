#!/usr/bin/env python3
"""Set all per-point content files to draft (or another status)."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--content-root",
        default="content/n5",
        help="Content root containing points/",
    )
    parser.add_argument(
        "--status",
        default="draft",
        choices=["draft", "needsRevision", "approved"],
        help="Status to assign",
    )
    args = parser.parse_args()

    points_dir = Path(args.content_root) / "points"
    updated = 0
    for path in sorted(points_dir.glob("*.json")):
        point = json.loads(path.read_text(encoding="utf-8"))
        if point.get("status") == args.status:
            continue
        point["status"] = args.status
        path.write_text(json.dumps(point, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        updated += 1

    print(f"Set {updated} points to '{args.status}' in {points_dir}")


if __name__ == "__main__":
    main()
