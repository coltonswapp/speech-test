#!/usr/bin/env python3
"""Merge approved per-point content files into bundled n5.grammar.json."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def lint_point(point: dict) -> list[str]:
    errors: list[str] = []
    pid = point.get("id", "")
    if not pid:
        errors.append("Point missing id")
    if not point.get("title"):
        errors.append(f"{pid}: missing title")
    if len(point.get("examples", [])) < 1:
        errors.append(f"{pid}: needs at least one example")
    for drill in point.get("drills", []):
        if not drill.get("correctChoice"):
            errors.append(f"{pid}: drill missing correctChoice")
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--content-root", default="content/n5")
    parser.add_argument("--output", default="shizen/Resources/Grammar/n5.grammar.json")
    args = parser.parse_args()

    content_root = Path(args.content_root)
    points_dir = content_root / "points"
    checkpoints_path = content_root / "checkpoints.json"

    checkpoints_data = json.loads(checkpoints_path.read_text(encoding="utf-8"))
    jlpt_level = checkpoints_data.get("jlptLevel", 5)
    checkpoints = checkpoints_data.get("checkpoints", [])

    approved: list[dict] = []
    for path in sorted(points_dir.glob("*.json")):
        point = json.loads(path.read_text(encoding="utf-8"))
        if point.get("status") != "approved":
            continue
        shipping = {k: v for k, v in point.items() if k not in ("status", "reviewNotes", "_provenance")}
        errors = lint_point(shipping)
        if errors:
            raise SystemExit("\n".join(errors))
        approved.append(shipping)

    approved.sort(key=lambda p: p.get("orderIndex", 0))
    approved_ids = {p["id"] for p in approved}
    approved_by_id = {p["id"]: p for p in approved}

    out_path = Path(args.output)
    existing_points: list[dict] = []
    existing_checkpoints: list[dict] = []
    if out_path.exists():
        existing = json.loads(out_path.read_text(encoding="utf-8"))
        existing_points = existing.get("points", [])
        existing_checkpoints = existing.get("checkpoints", [])

    points_by_id = {p["id"]: p for p in existing_points}
    updated_ids = []
    added_ids = []
    for point in approved:
        if point["id"] in points_by_id:
            updated_ids.append(point["id"])
        else:
            added_ids.append(point["id"])
        points_by_id[point["id"]] = point

    merged_points = sorted(points_by_id.values(), key=lambda p: (p.get("orderIndex", 0), p.get("id", "")))
    merged_point_ids = set(points_by_id.keys())
    preserved_count = len(existing_points) - len(updated_ids)

    checkpoints_by_id = {c["id"]: c for c in existing_checkpoints}
    for checkpoint in checkpoints:
        checkpoint_id = checkpoint["id"]
        existing_checkpoint = checkpoints_by_id.get(checkpoint_id, {})
        existing_point_ids = existing_checkpoint.get("pointIDs", [])
        merged_point_id_list = [pid for pid in existing_point_ids if pid in merged_point_ids]
        merged_set = set(merged_point_id_list)
        for point_id in checkpoint.get("pointIDs", []):
            if point_id in approved_ids and point_id not in merged_set:
                merged_point_id_list.append(point_id)
                merged_set.add(point_id)

        touches_approved = any(pid in approved_ids for pid in checkpoint.get("pointIDs", []))
        if touches_approved or checkpoint_id not in checkpoints_by_id:
            checkpoints_by_id[checkpoint_id] = {
                **checkpoint,
                "pointIDs": merged_point_id_list,
            }
        else:
            checkpoints_by_id[checkpoint_id] = {
                **existing_checkpoint,
                "pointIDs": merged_point_id_list,
            }

    for checkpoint in existing_checkpoints:
        checkpoint_id = checkpoint["id"]
        if checkpoint_id in checkpoints_by_id:
            continue
        point_ids = [pid for pid in checkpoint.get("pointIDs", []) if pid in merged_point_ids]
        if point_ids:
            checkpoints_by_id[checkpoint_id] = {**checkpoint, "pointIDs": point_ids}

    merged_checkpoints = sorted(
        checkpoints_by_id.values(),
        key=lambda c: (c.get("orderIndex", 0), c.get("id", "")),
    )

    output = {
        "formatVersion": 2,
        "jlptLevel": jlpt_level,
        "checkpoints": merged_checkpoints,
        "points": merged_points,
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if existing_points:
        shipped = len(updated_ids) + len(added_ids)
        print(
            f"Patched {shipped} approved points "
            f"({preserved_count} unchanged, {len(merged_points)} total) into {out_path}"
        )
    else:
        print(f"Created bundle with {len(approved)} approved points at {out_path}")


if __name__ == "__main__":
    main()
