#!/usr/bin/env python3
"""
Build cedict.sqlite from CC-CEDICT for the shizen-chinese target.

Simplified headwords only. FTS5 covers hanzi, numbered pinyin, toneless pinyin,
marked pinyin, and English glosses.

Usage:
    python3 scripts/build_cedict.py
    python3 scripts/build_cedict.py --txt /path/to/cedict_ts.u8
    python3 scripts/build_cedict.py --out shizen-chinese/cedict.sqlite
"""

from __future__ import annotations

import argparse
import gzip
import os
import re
import sqlite3
import sys
import urllib.request

CEDICT_URL = (
    "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
)

LINE_RE = re.compile(
    r"^(\S+)\s+(\S+)\s+\[([^\]]+)\]\s+/(.+)/$"
)

TONE_MARKS = {
    "a": "āáǎàa",
    "e": "ēéěèe",
    "i": "īíǐìi",
    "o": "ōóǒòo",
    "u": "ūúǔùu",
    "ü": "ǖǘǚǜü",
}


def numbered_syllable_to_marked(syllable: str) -> str:
    if not syllable:
        return syllable
    tone = 5
    body = syllable
    if body[-1].isdigit():
        tone = int(body[-1])
        body = body[:-1]
    body = body.replace("u:", "ü").replace("U:", "Ü").replace("v", "ü").replace("V", "ü")
    if tone not in (1, 2, 3, 4):
        return body

    lower = body.lower()
    idx = -1
    for i, ch in enumerate(lower):
        if ch == "a":
            idx = i
            break
    if idx < 0:
        for i, ch in enumerate(lower):
            if ch == "e":
                idx = i
                break
    if idx < 0:
        ou = lower.find("ou")
        if ou >= 0:
            idx = ou
    if idx < 0:
        for i in range(len(lower) - 1, -1, -1):
            if lower[i] in "iouü":
                idx = i
                break
    if idx < 0:
        return body

    ch = body[idx]
    key = ch.lower()
    marks = TONE_MARKS.get(key)
    if not marks:
        return body
    marked = marks[tone - 1]
    if ch.isupper():
        marked = marked.upper()
    return body[:idx] + marked + body[idx + 1 :]


def numbered_to_marked(pinyin: str) -> str:
    parts = pinyin.split()
    return " ".join(numbered_syllable_to_marked(part) for part in parts)


def numbered_to_plain(pinyin: str) -> str:
    stripped = re.sub(r"[0-9]", "", pinyin)
    return stripped.replace("u:", "u").replace("v", "u").lower()


def entry_score(simplified: str, glossary: str) -> int:
    length = len(simplified)
    if length <= 1:
        score = 1000
    elif length == 2:
        score = 900
    elif length == 3:
        score = 700
    else:
        score = max(80, 500 - min(length, 20) * 15)

    lowered = glossary.lower()
    if lowered.startswith("variant of") or lowered.startswith("see "):
        score -= 200
    if lowered.startswith("surname "):
        score -= 80
    return score


def iter_entries(txt_path: str):
    with open(txt_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            match = LINE_RE.match(line)
            if not match:
                continue
            _traditional, simplified, pinyin_numbered, gloss_raw = match.groups()
            glosses = [part.strip() for part in gloss_raw.split("/") if part.strip()]
            if not glosses:
                continue
            glossary = "; ".join(glosses)
            pinyin_numbered = pinyin_numbered.strip()
            yield {
                "simplified": simplified,
                "pinyin_numbered": pinyin_numbered,
                "pinyin_marked": numbered_to_marked(pinyin_numbered),
                "pinyin_plain": numbered_to_plain(pinyin_numbered),
                "glossary": glossary,
                "score": entry_score(simplified, glossary),
            }


DDL = """
CREATE TABLE IF NOT EXISTS entries (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    simplified       TEXT    NOT NULL,
    pinyin_numbered  TEXT    NOT NULL,
    pinyin_marked    TEXT    NOT NULL,
    pinyin_plain     TEXT    NOT NULL,
    glossary         TEXT    NOT NULL,
    score            INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_entries_simplified ON entries(simplified);
CREATE INDEX IF NOT EXISTS idx_entries_pinyin_plain ON entries(pinyin_plain);
CREATE INDEX IF NOT EXISTS idx_entries_score ON entries(score DESC);

CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
    simplified,
    pinyin_numbered,
    pinyin_plain,
    pinyin_marked,
    glossary,
    tokenize='unicode61 remove_diacritics 1'
);
"""


def build_db(txt_path: str, out_path: str):
    if os.path.exists(out_path):
        os.remove(out_path)

    con = sqlite3.connect(out_path)
    con.execute("PRAGMA journal_mode=DELETE")
    con.execute("PRAGMA synchronous=NORMAL")
    con.executescript(DDL)

    print("Parsing CC-CEDICT and inserting rows…")
    batch = []
    total = 0

    def flush():
        con.executemany(
            """INSERT INTO entries
               (simplified, pinyin_numbered, pinyin_marked, pinyin_plain, glossary, score)
               VALUES (:simplified, :pinyin_numbered, :pinyin_marked,
                       :pinyin_plain, :glossary, :score)""",
            batch,
        )
        batch.clear()

    for entry in iter_entries(txt_path):
        batch.append(entry)
        total += 1
        if total % 10000 == 0:
            flush()
            print(f"  {total} rows…", end="\r", flush=True)

    if batch:
        flush()

    print(f"\n{total} entries inserted. Building FTS index…")
    cur = con.execute(
        """SELECT id, simplified, pinyin_numbered, pinyin_plain, pinyin_marked, glossary
           FROM entries ORDER BY id"""
    )
    con.executemany(
        """INSERT INTO entries_fts(
               rowid, simplified, pinyin_numbered, pinyin_plain, pinyin_marked, glossary
           ) VALUES (?,?,?,?,?,?)""",
        cur,
    )

    print("Optimizing FTS index…")
    con.execute("INSERT INTO entries_fts(entries_fts) VALUES('optimize')")
    con.execute("PRAGMA integrity_check")
    con.commit()
    con.close()

    size_mb = os.path.getsize(out_path) / (1024 * 1024)
    print(f"Done. {total} rows → {out_path} ({size_mb:.1f} MB)")


def download_and_extract(dest_txt: str):
    gz_path = dest_txt + ".gz"
    print(f"Downloading {CEDICT_URL} …")

    def progress(block_num, block_size, total_size):
        downloaded = block_num * block_size
        if total_size > 0:
            pct = min(100, downloaded * 100 // total_size)
            print(f"  {pct}%", end="\r", flush=True)

    urllib.request.urlretrieve(CEDICT_URL, gz_path, reporthook=progress)
    print(f"\nExtracting to {dest_txt} …")
    with gzip.open(gz_path, "rb") as f_in, open(dest_txt, "wb") as f_out:
        while chunk := f_in.read(1 << 20):
            f_out.write(chunk)
    os.remove(gz_path)
    print("Extracted.")


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    parser = argparse.ArgumentParser(description="Build cedict.sqlite from CC-CEDICT")
    parser.add_argument("--txt", default=None, help="Path to uncompressed CC-CEDICT text")
    parser.add_argument(
        "--out",
        default=os.path.join(repo_root, "shizen-chinese", "cedict.sqlite"),
        help="Output SQLite path (default: shizen-chinese/cedict.sqlite)",
    )
    args = parser.parse_args()

    txt_path = args.txt
    if txt_path is None:
        txt_path = os.path.join(repo_root, "cedict_ts.u8")
        if not os.path.exists(txt_path):
            download_and_extract(txt_path)

    if not os.path.exists(txt_path):
        print(f"ERROR: CEDICT text not found at {txt_path}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    build_db(txt_path, args.out)


if __name__ == "__main__":
    main()
