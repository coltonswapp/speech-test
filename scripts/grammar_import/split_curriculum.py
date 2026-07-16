#!/usr/bin/env python3
"""Split bundled n5.grammar.json into per-point content files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        default="shizen/Resources/Grammar/n5.grammar.json",
        help="Bundled curriculum JSON",
    )
    parser.add_argument(
        "--output-root",
        default="content/n5",
        help="Output content root (points/ + checkpoints.json)",
    )
    parser.add_argument(
        "--default-status",
        default="draft",
        choices=["draft", "needsRevision", "approved"],
        help="Status assigned to split points",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_root = Path(args.output_root)
    points_dir = output_root / "points"
    points_dir.mkdir(parents=True, exist_ok=True)

    data = json.loads(input_path.read_text(encoding="utf-8"))
    checkpoints = data.get("checkpoints", [])
    jlpt_level = data.get("jlptLevel", 5)

    (output_root / "checkpoints.json").write_text(
        json.dumps({"jlptLevel": jlpt_level, "checkpoints": checkpoints}, indent=2, ensure_ascii=False)
        + "\n",
        encoding="utf-8",
    )

    for point in data.get("points", []):
        point = dict(point)
        point.setdefault("status", args.default_status)
        point.setdefault("relatedPointIDs", [])
        point_id = point["id"]
        out_path = points_dir / f"{point_id}.json"
        out_path.write_text(json.dumps(point, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"Wrote {len(data.get('points', []))} points to {points_dir}")
    print(f"Wrote checkpoints to {output_root / 'checkpoints.json'}")


if __name__ == "__main__":
    main()
