#!/usr/bin/env python3
"""Migrate grammar point files to reference schema (format v2)."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def infer_register(point: dict) -> str | None:
    for ladder in point.get("usageLadders") or []:
        for level in ladder.get("levels") or []:
            register = (level.get("register") or "").lower()
            if "casual" in register:
                return "casual"
            if "formal" in register or "keigo" in register:
                return "formal"
            if "polite" in register:
                return "polite"
    return None


def flatten_formation(point: dict) -> str | None:
    blocks = point.get("formation") or []
    bodies = [b.get("body", "").strip() for b in blocks if b.get("body")]
    joined = "\n\n".join(bodies)
    return joined or None


def extract_contrast_drills(point: dict) -> list[dict]:
    explicit = point.get("contrastDrills")
    if explicit:
        return explicit

    drills: list[dict] = []
    for drill in point.get("drills") or []:
        if drill.get("kind") != "contrastChoice":
            continue
        drills.append(
            {
                "contrastLabel": drill.get("contrastLabel") or "",
                "choices": drill.get("choices") or [],
                "correctChoice": drill.get("correctChoice") or "",
                "ruleTargeted": drill.get("instruction"),
            }
        )
    return drills


def migrate_point(point: dict) -> dict:
    migrated = dict(point)

    migrated["pattern"] = point.get("pattern") or point.get("title") or ""
    migrated["shortDefinition"] = point.get("shortDefinition") or point.get("headlineEnglish") or ""
    forms = point.get("forms") or []
    migrated["reading"] = point.get("reading") or (forms[0] if forms else migrated["pattern"])

    structure = point.get("structure") or flatten_formation(point)
    if structure:
        migrated["structure"] = structure

    register = point.get("register") or infer_register(point)
    if register:
        migrated["register"] = register

    contrast_drills = extract_contrast_drills(point)
    if contrast_drills:
        migrated["contrastDrills"] = contrast_drills

    return migrated


def shipping_point(point: dict) -> dict:
    """Shape for bundled n5.grammar.json (reference fields only)."""
    return {
        "id": point["id"],
        "orderIndex": point.get("orderIndex", 0),
        "pattern": point.get("pattern") or point.get("title", ""),
        "reading": point.get("reading"),
        "shortDefinition": point.get("shortDefinition") or point.get("headlineEnglish", ""),
        "blurb": point.get("blurb"),
        "structure": point.get("structure"),
        "register": point.get("register"),
        "forms": point.get("forms") or [],
        "relatedPointIDs": point.get("relatedPointIDs") or [],
        "examples": point.get("examples") or [],
        "contrastDrills": point.get("contrastDrills") or extract_contrast_drills(point),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--content-root", default="content/n5")
    parser.add_argument("--output", default="shizen/Resources/Grammar/n5.grammar.json")
    parser.add_argument("--write-points", action="store_true", help="Update per-point JSON files in place")
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
        migrated = migrate_point(point)
        if args.write_points:
            path.write_text(json.dumps(migrated, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        if migrated.get("status") != "approved":
            continue
        approved.append(shipping_point(migrated))

    approved.sort(key=lambda p: p.get("orderIndex", 0))
    approved_ids = {p["id"] for p in approved}

    out_path = Path(args.output)
    existing_points: list[dict] = []
    existing_checkpoints: list[dict] = []
    if out_path.exists():
        existing = json.loads(out_path.read_text(encoding="utf-8"))
        existing_points = existing.get("points", [])
        existing_checkpoints = existing.get("checkpoints", [])

    points_by_id = {p["id"]: p for p in existing_points}
    updated_ids: list[str] = []
    added_ids: list[str] = []
    for point in approved:
        if point["id"] in points_by_id:
            updated_ids.append(point["id"])
        else:
            added_ids.append(point["id"])
        points_by_id[point["id"]] = point

    merged_points = sorted(points_by_id.values(), key=lambda p: (p.get("orderIndex", 0), p.get("id", "")))
    merged_point_ids = set(points_by_id.keys())

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
        checkpoints_by_id[checkpoint_id] = {
            "id": checkpoint_id,
            "orderIndex": checkpoint.get("orderIndex", 0),
            "title": checkpoint.get("title", ""),
            "subtitle": checkpoint.get("subtitle"),
            "pointIDs": merged_point_id_list,
        }

    merged_checkpoints = sorted(checkpoints_by_id.values(), key=lambda c: (c.get("orderIndex", 0), c.get("id", "")))

    bundle = {
        "formatVersion": 2,
        "jlptLevel": jlpt_level,
        "checkpoints": merged_checkpoints,
        "points": merged_points,
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(bundle, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"Migrated {len(list(points_dir.glob('*.json')))} point files")
    print(f"Approved shipping points: {len(approved)}")
    print(f"Updated bundle: {out_path}")
    print(f"Updated: {len(updated_ids)}, added: {len(added_ids)}, total: {len(merged_points)}")


if __name__ == "__main__":
    main()
