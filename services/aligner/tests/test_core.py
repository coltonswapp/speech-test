"""Unit checks for romanization. Run: python tests/test_core.py"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from aligner.core import romanize, is_kana

assert is_kana("さんまるに") and is_kana("カイトー") and not is_kana("三〇二") and not is_kana("302")
# A kana reading wins and is not a fallback.
assert romanize("三〇二", "さんまるに") == ("sanmaruni", False)
assert romanize("302", "さんまるに") == ("sanmaruni", False)
# Non-kana reading is ignored → override table.
assert romanize("三〇二", "302") == ("sanmaruni", True)
assert romanize("302") == ("sanmaruni", True)
# Plain surface → pykakasi.
assert romanize("すみません") == ("sumimasen", True)
assert romanize("日本", "にほん") == ("nihon", False)
# Nothing alignable still yields one target.
assert romanize("ー") == ("a", True)
assert romanize("…") == ("a", True)
print("test_core OK")
