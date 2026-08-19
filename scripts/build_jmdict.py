#!/usr/bin/env python3
"""
build_jmdict.py — Convert JMdict_e.xml to jmdict.sqlite

Usage:
    python3 scripts/build_jmdict.py [--xml path/to/JMdict_e.xml] [--out path/to/jmdict.sqlite]

If --xml is omitted, downloads JMdict_e.gz from the Monash FTP mirror and extracts it.
If --out is omitted, writes to shizen/jmdict.sqlite (bundled by the iOS app).

Schema produced:
    entries(id, sequence, expression, reading, primary_reading, glossary, info, tags, score)
    entries_fts  — FTS5 over (expression, reading, romaji, glossary), content=entries
    entries_fts_romaji_col stores the pre-computed romaji so the Swift side never has to convert

Priority score mapping (higher = more common):
    news1/ichi1/spec1  +2000 each
    news2/ichi2/spec2  +1000 each
    gai1               +1500
    gai2               +500
    nf01–nf24          +600 − (rank*25)  (nf01 most frequent)
"""

import argparse
import gzip
import os
import sqlite3
import sys
import urllib.request
import xml.etree.ElementTree as ET

JMDICT_URL = "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz"

# ── Romaji conversion ─────────────────────────────────────────────────────────

YOON = {
    "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
    "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
    "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
    "じゃ": "ja",  "じゅ": "ju",  "じょ": "jo",
    "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
    "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
    "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
    "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
    "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
    "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
    "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
}

KANA = {
    "あ": "a",  "い": "i",   "う": "u",   "え": "e",  "お": "o",
    "か": "ka", "き": "ki",  "く": "ku",  "け": "ke", "こ": "ko",
    "さ": "sa", "し": "shi", "す": "su",  "せ": "se", "そ": "so",
    "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
    "な": "na", "に": "ni",  "ぬ": "nu",  "ね": "ne", "の": "no",
    "は": "ha", "ひ": "hi",  "ふ": "fu",  "へ": "he", "ほ": "ho",
    "ま": "ma", "み": "mi",  "む": "mu",  "め": "me", "も": "mo",
    "や": "ya", "ゆ": "yu",  "よ": "yo",
    "ら": "ra", "り": "ri",  "る": "ru",  "れ": "re", "ろ": "ro",
    "わ": "wa", "を": "wo",  "ん": "n",
    "が": "ga", "ぎ": "gi",  "ぐ": "gu",  "げ": "ge", "ご": "go",
    "ざ": "za", "じ": "ji",  "ず": "zu",  "ぜ": "ze", "ぞ": "zo",
    "だ": "da", "ぢ": "ji",  "づ": "zu",  "で": "de", "ど": "do",
    "ば": "ba", "び": "bi",  "ぶ": "bu",  "べ": "be", "ぼ": "bo",
    "ぱ": "pa", "ぴ": "pi",  "ぷ": "pu",  "ぺ": "pe", "ぽ": "po",
    "ー": "-",
}

KATA_TO_HIRA_OFFSET = ord("あ") - ord("ア")


def kata_to_hira(text: str) -> str:
    result = []
    for ch in text:
        cp = ord(ch)
        if 0x30A1 <= cp <= 0x30F6:
            result.append(chr(cp + KATA_TO_HIRA_OFFSET))
        else:
            result.append(ch)
    return "".join(result)


def kana_to_romaji(text: str) -> str:
    normalized = kata_to_hira(text)
    chars = list(normalized)
    result = []
    i = 0
    while i < len(chars):
        if chars[i] == "っ":
            if i + 1 < len(chars):
                pair = chars[i + 1] + (chars[i + 2] if i + 2 < len(chars) else "")
                if pair in YOON:
                    result.append(YOON[pair][0])
                elif chars[i + 1] in KANA:
                    result.append(KANA[chars[i + 1]][0])
            i += 1
            continue
        if i + 1 < len(chars):
            pair = chars[i] + chars[i + 1]
            if pair in YOON:
                result.append(YOON[pair])
                i += 2
                continue
        ch = chars[i]
        if ch in KANA:
            result.append(KANA[ch])
        else:
            result.append(ch)
        i += 1
    return "".join(result)


# ── Priority score ────────────────────────────────────────────────────────────

def priority_score(pri_elements: list[str]) -> int:
    score = 0
    for p in pri_elements:
        if p in ("news1", "ichi1", "spec1"):
            score += 2000
        elif p in ("news2", "ichi2", "spec2"):
            score += 1000
        elif p == "gai1":
            score += 1500
        elif p == "gai2":
            score += 500
        elif p.startswith("nf"):
            try:
                rank = int(p[2:])
                score += max(0, 600 - rank * 25)
            except ValueError:
                pass
    return score


# ── Part-of-speech tag normalizer ─────────────────────────────────────────────

KNOWN_POS = {
    "noun (common) (futsuumeishi)": "n",
    "Ichidan verb": "v1",
    "Godan verb with 'u' ending": "v5u",
    "Godan verb with 'ku' ending": "v5k",
    "Godan verb with 'gu' ending": "v5g",
    "Godan verb with 'su' ending": "v5s",
    "Godan verb with 'tsu' ending": "v5t",
    "Godan verb with 'nu' ending": "v5n",
    "Godan verb with 'bu' ending": "v5b",
    "Godan verb with 'mu' ending": "v5m",
    "Godan verb with 'ru' ending (irregular verb)": "v5r-i",
    "Godan verb with 'ru' ending": "v5r",
    "suru verb - included": "vs-i",
    "suru verb - special class": "vs-s",
    "noun or verb acting prenominally": "adj-f",
    "adjective (keiyoushi)": "adj-i",
    "adjectival nouns or quasi-adjectives (keiyodoshi)": "adj-na",
    "adverb (fukushi)": "adv",
    "adverb taking the 'to' particle": "adv-to",
    "auxiliary verb": "aux-v",
    "conjunction": "conj",
    "counter": "ctr",
    "expression (phrase, clause, etc.)": "exp",
    "interjection (kandoushi)": "int",
    "numeric": "num",
    "particle": "prt",
    "prefix": "pref",
    "suffix": "suf",
    "pronoun": "pn",
}


def normalize_pos(pos_text: str) -> str:
    return KNOWN_POS.get(pos_text, pos_text[:20] if pos_text else "")


# ── XML parsing ───────────────────────────────────────────────────────────────

def iter_entries(xml_path: str):
    """Yield dicts for each JMdict <entry>."""
    context = ET.iterparse(xml_path, events=("end",))
    for event, elem in context:
        if elem.tag != "entry":
            continue

        seq = int(elem.findtext("ent_seq", "0"))

        # Kanji elements (k_ele) — expression forms
        k_eles = elem.findall("k_ele")
        kanji_forms = []
        kanji_pris = []
        for k in k_eles:
            keb = k.findtext("keb", "").strip()
            if keb:
                kanji_forms.append(keb)
                kanji_pris.extend(p.text for p in k.findall("ke_pri") if p.text)

        # Reading elements (r_ele)
        r_eles = elem.findall("r_ele")
        readings = []
        reading_pris = []
        for r in r_eles:
            reb = r.findtext("reb", "").strip()
            if reb:
                readings.append(reb)
                reading_pris.extend(p.text for p in r.findall("re_pri") if p.text)

        if not readings:
            elem.clear()
            continue

        all_pris = kanji_pris + reading_pris
        score = priority_score(all_pris)

        # Sense elements
        senses = elem.findall("sense")
        for sense in senses:
            # Skip non-English senses (lsource with xml:lang != en)
            lsources = sense.findall("lsource")
            if lsources:
                langs = [ls.get("{http://www.w3.org/XML/1998/namespace}lang", "eng") for ls in lsources]
                if any(l not in ("eng", "en") for l in langs):
                    continue

            glosses = [g.text.strip() for g in sense.findall("gloss") if g.text]
            if not glosses:
                continue

            pos_tags = [normalize_pos(p.text) for p in sense.findall("pos") if p.text]
            misc_tags = [m.text for m in sense.findall("misc") if m.text]
            field_tags = [f.text for f in sense.findall("field") if f.text]
            info_parts = [i.text for i in sense.findall("s_inf") if i.text]

            tags_str = " ".join(filter(None, pos_tags + misc_tags)) or None
            info_str = "; ".join(filter(None, info_parts + field_tags)) or None
            glossary_str = "; ".join(glosses)

            expression = kanji_forms[0] if kanji_forms else readings[0]
            reading = readings[0]

            # primary_reading: only set when we have kanji + the reading differs from expression
            primary_reading = reading if kanji_forms else None

            yield {
                "sequence": seq,
                "expression": expression,
                "reading": reading,
                "primary_reading": primary_reading,
                "glossary": glossary_str,
                "info": info_str,
                "tags": tags_str,
                "score": score,
            }

        elem.clear()


# ── Database ──────────────────────────────────────────────────────────────────

DDL = """
CREATE TABLE IF NOT EXISTS entries (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    sequence        INTEGER NOT NULL,
    expression      TEXT    NOT NULL,
    reading         TEXT    NOT NULL,
    primary_reading TEXT,
    glossary        TEXT    NOT NULL,
    info            TEXT,
    tags            TEXT,
    score           INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_entries_expression ON entries(expression);
CREATE INDEX IF NOT EXISTS idx_entries_reading    ON entries(reading);
-- Required by hasExactLexicalMatch's OR query: SQLite only applies the
-- OR-to-index optimization when every arm is indexable; without this index
-- each lookup falls back to a full table scan (~250k rows).
CREATE INDEX IF NOT EXISTS idx_entries_primary_reading ON entries(primary_reading);
CREATE INDEX IF NOT EXISTS idx_entries_score      ON entries(score DESC);

-- romaji is a fully indexed column so prefix queries like "tabe*" hit it.
-- It is NOT in the entries table; we populate it manually in the FTS insert pass.
CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
    expression,
    reading,
    romaji,
    glossary,
    tokenize='unicode61 remove_diacritics 1'
);
"""

TRIGGERS = """
CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
    INSERT INTO entries_fts(rowid, expression, reading, romaji, glossary)
    VALUES (new.id, new.expression, new.reading, new.romaji_placeholder, new.glossary);
END;
"""

# We insert romaji via a separate entries_fts_data insert instead of triggers,
# to avoid adding a column to entries. The FTS table is populated manually below.


def build_db(xml_path: str, out_path: str):
    if os.path.exists(out_path):
        os.remove(out_path)

    con = sqlite3.connect(out_path)
    con.execute("PRAGMA journal_mode=DELETE")
    con.execute("PRAGMA synchronous=NORMAL")

    con.executescript(DDL)

    print("Parsing XML and inserting rows…")
    batch = []
    total = 0

    def flush():
        con.executemany(
            """INSERT INTO entries
               (sequence, expression, reading, primary_reading, glossary, info, tags, score)
               VALUES (:sequence, :expression, :reading, :primary_reading,
                       :glossary, :info, :tags, :score)""",
            batch,
        )
        batch.clear()

    for entry in iter_entries(xml_path):
        batch.append(entry)
        total += 1
        if total % 10000 == 0:
            flush()
            print(f"  {total} rows…", end="\r", flush=True)

    if batch:
        flush()

    # Build FTS in a second pass so rowids are authoritative from the DB.
    print(f"\n{total} entries inserted. Building FTS index…")
    cur = con.execute("SELECT id, expression, reading, glossary FROM entries ORDER BY id")

    def fts_rows():
        for row_id, expression, reading, glossary in cur:
            romaji = kana_to_romaji(reading)
            yield (row_id, expression, reading, romaji, glossary)

    con.executemany(
        "INSERT INTO entries_fts(rowid, expression, reading, romaji, glossary) VALUES (?,?,?,?,?)",
        fts_rows(),
    )

    print("Optimizing FTS index…")
    con.execute("INSERT INTO entries_fts(entries_fts) VALUES('optimize')")

    con.execute("PRAGMA integrity_check")
    con.commit()
    con.close()

    size_mb = os.path.getsize(out_path) / (1024 * 1024)
    print(f"Done. {total} rows → {out_path} ({size_mb:.1f} MB)")


# ── Download ──────────────────────────────────────────────────────────────────

def download_and_extract(dest_xml: str):
    gz_path = dest_xml + ".gz"
    print(f"Downloading {JMDICT_URL} …")

    def progress(block_num, block_size, total_size):
        downloaded = block_num * block_size
        if total_size > 0:
            pct = min(100, downloaded * 100 // total_size)
            print(f"  {pct}%", end="\r", flush=True)

    urllib.request.urlretrieve(JMDICT_URL, gz_path, reporthook=progress)
    print(f"\nExtracting to {dest_xml} …")
    with gzip.open(gz_path, "rb") as f_in, open(dest_xml, "wb") as f_out:
        while chunk := f_in.read(1 << 20):
            f_out.write(chunk)
    os.remove(gz_path)
    print("Extracted.")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    parser = argparse.ArgumentParser(description="Build jmdict.sqlite from JMdict XML")
    parser.add_argument("--xml", default=None, help="Path to JMdict_e.xml (downloaded if omitted)")
    parser.add_argument(
        "--out",
        default=os.path.join(repo_root, "shizen", "jmdict.sqlite"),
        help="Output SQLite path (default: shizen/jmdict.sqlite)",
    )
    args = parser.parse_args()

    xml_path = args.xml
    if xml_path is None:
        xml_path = os.path.join(repo_root, "JMdict_e.xml")
        if not os.path.exists(xml_path):
            download_and_extract(xml_path)

    if not os.path.exists(xml_path):
        print(f"ERROR: XML not found at {xml_path}", file=sys.stderr)
        sys.exit(1)

    build_db(xml_path, args.out)


if __name__ == "__main__":
    main()
