const DIGRAPHS: Record<string, string> = {
  きゃ: "kya",
  きゅ: "kyu",
  きょ: "kyo",
  しゃ: "sha",
  しゅ: "shu",
  しょ: "sho",
  ちゃ: "cha",
  ちゅ: "chu",
  ちょ: "cho",
  にゃ: "nya",
  にゅ: "nyu",
  にょ: "nyo",
  ひゃ: "hya",
  ひゅ: "hyu",
  ひょ: "hyo",
  みゃ: "mya",
  みゅ: "myu",
  みょ: "myo",
  りゃ: "rya",
  りゅ: "ryu",
  りょ: "ryo",
  ぎゃ: "gya",
  ぎゅ: "gyu",
  ぎょ: "gyo",
  じゃ: "ja",
  じゅ: "ju",
  じょ: "jo",
  びゃ: "bya",
  びゅ: "byu",
  びょ: "byo",
  ぴゃ: "pya",
  ぴゅ: "pyu",
  ぴょ: "pyo",
};

const KANA: Record<string, string> = {
  あ: "a",
  い: "i",
  う: "u",
  え: "e",
  お: "o",
  か: "ka",
  き: "ki",
  く: "ku",
  け: "ke",
  こ: "ko",
  さ: "sa",
  し: "shi",
  す: "su",
  せ: "se",
  そ: "so",
  た: "ta",
  ち: "chi",
  つ: "tsu",
  て: "te",
  と: "to",
  な: "na",
  に: "ni",
  ぬ: "nu",
  ね: "ne",
  の: "no",
  は: "ha",
  ひ: "hi",
  ふ: "fu",
  へ: "he",
  ほ: "ho",
  ま: "ma",
  み: "mi",
  む: "mu",
  め: "me",
  も: "mo",
  や: "ya",
  ゆ: "yu",
  よ: "yo",
  ら: "ra",
  り: "ri",
  る: "ru",
  れ: "re",
  ろ: "ro",
  わ: "wa",
  を: "o",
  ん: "n",
  が: "ga",
  ぎ: "gi",
  ぐ: "gu",
  げ: "ge",
  ご: "go",
  ざ: "za",
  じ: "ji",
  ず: "zu",
  ぜ: "ze",
  ぞ: "zo",
  だ: "da",
  ぢ: "ji",
  づ: "zu",
  で: "de",
  ど: "do",
  ば: "ba",
  び: "bi",
  ぶ: "bu",
  べ: "be",
  ぼ: "bo",
  ぱ: "pa",
  ぴ: "pi",
  ぷ: "pu",
  ぺ: "pe",
  ぽ: "po",
  ぁ: "a",
  ぃ: "i",
  ぅ: "u",
  ぇ: "e",
  ぉ: "o",
  ゃ: "ya",
  ゅ: "yu",
  ょ: "yo",
  ゎ: "wa",
  っ: "",
  ー: "",
};

function katakanaToHiragana(input: string): string {
  return Array.from(input)
    .map((char) => {
      const code = char.charCodeAt(0);
      if (code >= 0x30a1 && code <= 0x30f6) {
        return String.fromCharCode(code - 0x60);
      }
      return char;
    })
    .join("");
}

export function romanize(input: string): string {
  const hiragana = katakanaToHiragana(input.trim());
  let out = "";
  let i = 0;
  while (i < hiragana.length) {
    const pair = hiragana.slice(i, i + 2);
    if (hiragana[i] === "っ") {
      const next = hiragana.slice(i + 1, i + 3);
      const nextRomaji =
        DIGRAPHS[next] ?? KANA[hiragana[i + 1] ?? ""] ?? hiragana[i + 1] ?? "";
      const consonant = nextRomaji.match(/^[bcdfghjklmnpqrstvwxyz]/i)?.[0];
      out += consonant ?? "t";
      i += 1;
      continue;
    }
    if (hiragana[i] === "ー") {
      const lastVowel = out.match(/[aeiou]$/i)?.[0];
      if (lastVowel) out += lastVowel;
      i += 1;
      continue;
    }
    if (DIGRAPHS[pair]) {
      out += DIGRAPHS[pair];
      i += 2;
      continue;
    }
    if (KANA[hiragana[i]]) {
      out += KANA[hiragana[i]];
      i += 1;
      continue;
    }
    out += hiragana[i];
    i += 1;
  }
  return out;
}

export function readingLine(reading: string): string {
  const kana = reading.trim();
  const romaji = romanize(kana);
  if (!kana) return romaji;
  if (!romaji || romaji === kana) return kana;
  return `${kana} · ${romaji}`;
}

export function annotatedReadings(readings: string[], limit = 4): string {
  return readings
    .slice(0, limit)
    .map((reading) => {
      const romaji = romanize(reading);
      if (!romaji || romaji === reading) return reading;
      return `${reading} (${romaji})`;
    })
    .join("、");
}
