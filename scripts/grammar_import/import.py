#!/usr/bin/env python3
"""
Build-time importer: JLPT Sensei N5 grammar HTML → draft n5.grammar.json.

Usage:
  python3 import.py --index-url URL --output PATH
  python3 import.py --html-dir ./cached_pages --output ../../shizen/Resources/Grammar/n5.grammar.json

Does not run inside the app. Review and edit teaching copy before release.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from urllib.parse import urljoin, urlparse

DEFAULT_INDEX = "https://jlptsensei.com/jlpt-n5-grammar-list/"

USER_AGENT = "ShizenGrammarImport/1.0 (build-time editorial tool)"


@dataclass
class Example:
    japanese: str
    romaji: str
    english: str
    target_substring: Optional[str] = None
    source_url: str = ""


@dataclass
class DraftPoint:
    id: str
    order_index: int
    title: str
    headline_english: str
    forms: list[str]
    formation: list[dict]
    usage: list[dict]
    related_point_ids: list[str]
    examples: list[Example]
    drills: list[dict]
    source_url: str = ""
    imported_at: str = ""


def strip_tags(html_fragment: str) -> str:
    text = re.sub(r"<[^>]+>", "", html_fragment)
    return re.sub(r"\s+", " ", text).strip()


def slug_from_url(url: str) -> str:
    ascii_tail = re.search(r"([a-z][a-z0-9-]+(?:-[a-z][a-z0-9-]+)*)/?$", url)
    if ascii_tail:
        slug = ascii_tail.group(1)
    else:
        path = urlparse(url).path.rstrip("/")
        segment = path.split("/")[-1] if path else "unknown"
        from urllib.parse import unquote

        slug = re.sub(r"[^a-z0-9]+", "-", unquote(segment).lower()).strip("-")
    slug = slug.replace("-ja-dame", "").replace("-meaning", "")
    return f"n5-{slug}" if slug else "n5-unknown"


def parse_title(html: str) -> str:
    match = re.search(r"<h1[^>]*>(.*?)</h1>", html, flags=re.S | re.I)
    if not match:
        return ""
    title = strip_tags(match.group(1))
    title = re.sub(r"^JLPT N5 Grammar\s*", "", title, flags=re.I)
    title = re.sub(r"\s*\([^)]*\)\s*$", "", title).strip()
    return title


def parse_headline(html: str) -> str:
    match = re.search(r"Meaning:\s*([^<\n]+)", html, flags=re.I)
    if match:
        return match.group(1).strip().rstrip(".")
    match = re.search(r'<meta[^>]+name="description"[^>]+content="([^"]+)"', html, flags=re.I)
    if match:
        desc = match.group(1)
        if "Meaning:" in desc:
            return desc.split("Meaning:", 1)[1].split(".", 1)[0].strip()
        return desc[:120].strip()
    return ""


def parse_examples_from_html(html: str, source_url: str) -> list[Example]:
    examples: list[Example] = []
    jp_blocks = re.findall(
        r'example-main"><p class="m-0 jp">(.*?)</div>',
        html,
        flags=re.S | re.I,
    )
    for index, jp_raw in enumerate(jp_blocks[:10], start=1):
        japanese = strip_tags(jp_raw)
        if not japanese:
            continue
        romaji_match = re.search(
            rf'id=example_{index}_romaji.*?alert alert-info">([^<]+)',
            html,
            flags=re.S | re.I,
        )
        english_match = re.search(
            rf'id=example_{index}_en.*?alert alert-primary">([^<]+)',
            html,
            flags=re.S | re.I,
        )
        romaji = romaji_match.group(1).strip() if romaji_match else ""
        english = english_match.group(1).strip() if english_match else ""
        examples.append(Example(japanese=japanese, romaji=romaji, english=english, source_url=source_url))
    return examples


def fetch(url: str, delay: float) -> str:
    time.sleep(delay)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8", errors="replace")


def extract_grammar_links(index_html: str, base_url: str) -> list[str]:
    """JLPT Sensei list pages often use unquoted href= attributes."""
    raw = re.findall(r"href=([^\s>]+)", index_html)
    seen: set[str] = set()
    ordered: list[str] = []
    for href in raw:
        href = href.strip("\"'")
        if "learn-japanese-grammar" not in href:
            continue
        if href.startswith("/"):
            href = urljoin(base_url, href)
        if not href.startswith("http"):
            continue
        if href in seen:
            continue
        seen.add(href)
        ordered.append(href)
    return ordered


def guess_forms(title: str) -> list[str]:
    parts = re.split(r"[・/]", title)
    return [p.strip() for p in parts if p.strip()]


def suggest_target_substring(japanese: str, forms: list[str]) -> Optional[str]:
    for form in sorted(forms, key=len, reverse=True):
        stem = form.replace("いけない", "").replace("ダメ", "").replace("いけません", "")
        if stem and stem in japanese:
            idx = japanese.find(stem)
            end = min(len(japanese), idx + len(form) + 8)
            return japanese[idx:end]
    return None


def template_drills(point_id: str, examples: list[Example], forms: list[str]) -> list[dict]:
    drills: list[dict] = []
    if examples:
        ex = examples[0]
        drills.append(
            {
                "kind": "meaningChoice",
                "exampleJapanese": ex.japanese,
                "choices": [ex.english, "Opposite meaning.", "Unrelated phrase.", "Literal word order."],
                "correctChoice": ex.english,
            }
        )
        target = suggest_target_substring(ex.japanese, forms) or ""
        if target:
            drills.append(
                {
                    "kind": "sentenceBuilder",
                    "english": ex.english,
                    "buildComponents": [],
                    "choices": [],
                    "correctChoice": ex.japanese,
                }
            )
    if len(examples) >= 2:
        ex2 = examples[1]
        drills.append(
            {
                "kind": "sentenceChoice",
                "prompt": ex2.english,
                "choices": [ex2.japanese, examples[0].japanese if examples else ex2.japanese],
                "correctChoice": ex2.japanese,
            }
        )
    return drills


def parse_page(url: str, html: str, order_index: int) -> DraftPoint:
    title = parse_title(html) or slug_from_url(url)
    forms = guess_forms(title)
    headline = parse_headline(html) or title
    examples = parse_examples_from_html(html, source_url=url)[:5]
    for ex in examples:
        ex.target_substring = suggest_target_substring(ex.japanese, forms)
        ex.source_url = url

    formation = [
        {
            "title": "Formation",
            "body": "Review the lesson page and write Shizen formation notes here.",
            "_provenance": {"source": "jlptsensei", "url": url},
        }
    ]
    usage = [
        {
            "title": "Usage",
            "body": "Review the lesson page and write Shizen usage notes here.",
            "_provenance": {"source": "jlptsensei", "url": url},
        }
    ]

    return DraftPoint(
        id=slug_from_url(url),
        order_index=order_index,
        title=title,
        headline_english=headline,
        forms=forms,
        formation=formation,
        usage=usage,
        related_point_ids=[],
        examples=examples,
        drills=template_drills(slug_from_url(url), examples, forms),
        source_url=url,
        imported_at=time.strftime("%Y-%m-%d"),
    )


def lint_curriculum(data: dict) -> list[str]:
    errors: list[str] = []
    points = data.get("points", [])
    ids: set[str] = set()
    indices: list[int] = []
    for p in points:
        pid = p.get("id", "")
        if not pid:
            errors.append("Point missing id")
        if pid in ids:
            errors.append(f"Duplicate id: {pid}")
        ids.add(pid)
        idx = p.get("orderIndex", -1)
        indices.append(idx)
        if not p.get("title"):
            errors.append(f"{pid}: missing title")
        if len(p.get("examples", [])) < 1:
            errors.append(f"{pid}: needs at least one example")
        if len(p.get("examples", [])) > 10:
            errors.append(f"{pid}: too many examples ({len(p.get('examples', []))})")
        for d in p.get("drills", []):
            if not d.get("correctChoice"):
                errors.append(f"{pid}: drill missing correctChoice")
    if indices != sorted(indices):
        errors.append("orderIndex values are not sorted")
    if len(set(indices)) != len(indices):
        errors.append("Duplicate orderIndex values")
    return errors


def point_to_json(p: DraftPoint) -> dict:
    return {
        "id": p.id,
        "orderIndex": p.order_index,
        "title": p.title,
        "headlineEnglish": p.headline_english,
        "forms": p.forms,
        "formation": p.formation,
        "usage": p.usage,
        "relatedPointIDs": p.related_point_ids,
        "examples": [
            {
                "japanese": e.japanese,
                "romaji": e.romaji,
                "english": e.english,
                "targetSubstring": e.target_substring,
            }
            for e in p.examples
        ],
        "drills": p.drills,
        "_provenance": {
            "source": "jlptsensei",
            "url": p.source_url,
            "importedAt": p.imported_at,
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Import JLPT Sensei N5 grammar into draft JSON.")
    ap.add_argument("--index-url", default=DEFAULT_INDEX)
    ap.add_argument("--html-dir", type=Path, help="Directory of cached .html pages (slug.html)")
    ap.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "shizen/Resources/Grammar/n5.grammar.json",
    )
    ap.add_argument("--delay", type=float, default=1.0, help="Seconds between HTTP requests")
    ap.add_argument("--limit", type=int, default=0, help="Max points to import (0 = all)")
    ap.add_argument(
        "--pilots",
        type=Path,
        default=Path(__file__).resolve().parent / "pilots.json",
        help="Curated pilot points merged after import",
    )
    args = ap.parse_args()

    points: list[DraftPoint] = []

    if args.html_dir:
        html_files = sorted(args.html_dir.glob("*.html"))
        for i, path in enumerate(html_files):
            html = path.read_text(encoding="utf-8")
            url = f"file://{path.name}"
            points.append(parse_page(url, html, i))
    else:
        try:
            index_html = fetch(args.index_url, delay=0)
        except urllib.error.URLError as e:
            print(f"Failed to fetch index: {e}", file=sys.stderr)
            return 1
        links = extract_grammar_links(index_html, args.index_url)
        if args.limit > 0:
            links = links[: args.limit]
        print(f"Found {len(links)} grammar pages")
        for i, url in enumerate(links):
            print(f"[{i + 1}/{len(links)}] {url}")
            try:
                html = fetch(url, delay=args.delay)
            except urllib.error.URLError as e:
                print(f"  skip: {e}", file=sys.stderr)
                continue
            points.append(parse_page(url, html, i))

    imported_points = [point_to_json(p) for p in points if p.examples]
    imported_by_slug = {p["id"]: p for p in imported_points}

    pilot_points: list[dict] = []
    if args.pilots.exists():
        try:
            pilot_data = json.loads(args.pilots.read_text(encoding="utf-8"))
            pilot_points = pilot_data.get("points", [])
        except json.JSONDecodeError:
            print(f"Could not parse pilots file: {args.pilots}", file=sys.stderr)

    pilot_ids = {p["id"] for p in pilot_points}
    # Drop imported duplicates that match pilot URL slugs (e.g. cha-ikenai).
    filtered_imported = [
        p
        for p in imported_points
        if p["id"] not in pilot_ids and "cha-ikenai" not in p.get("_provenance", {}).get("url", "")
    ]

    out_points = list(pilot_points) + filtered_imported
    for index, point in enumerate(out_points):
        point["orderIndex"] = index

    curriculum = {
        "formatVersion": 1,
        "jlptLevel": 5,
        "points": out_points,
    }
    if args.output.exists():
        try:
            existing = json.loads(args.output.read_text(encoding="utf-8"))
            if existing.get("checkpoints"):
                curriculum["checkpoints"] = existing["checkpoints"]
        except (json.JSONDecodeError, OSError):
            pass

    errors = lint_curriculum(curriculum)
    if errors:
        print("Lint warnings/errors:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(curriculum, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(out_points)} points → {args.output}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
