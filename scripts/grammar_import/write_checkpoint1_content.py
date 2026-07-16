#!/usr/bin/env python3
"""Author checkpoint 1 (core particles) grammar content with short blurbs and varied examples."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POINTS_DIR = ROOT / "content/n5/points"
GRAMMAR_JSON = ROOT / "shizen/Resources/Grammar/n5.grammar.json"

CHECKPOINT1_IDS = [
    "n5-wa",
    "n5-ga-1",
    "n5-ga-2",
    "n5-ka-1",
    "n5-ka-2",
    "n5-ni",
    "n5-ni-e",
    "n5-de-1",
    "n5-de-2",
    "n5-mo",
]


def ex(japanese: str, romaji: str, english: str, target: str) -> dict:
    return {
        "japanese": japanese,
        "romaji": romaji,
        "english": english,
        "targetSubstring": target,
        "audioKey": None,
    }


def contrast(label: str, choices: list[str], correct: str) -> dict:
    return {
        "contrastLabel": label,
        "choices": choices,
        "correctChoice": correct,
        "ruleTargeted": None,
    }


def contrast_drills_from(point: dict) -> list[dict]:
    out: list[dict] = []
    for drill in point.get("drills", []):
        if drill.get("kind") != "contrastChoice":
            continue
        out.append(
            contrast(
                drill.get("contrastLabel", ""),
                drill["choices"],
                drill["correctChoice"],
            )
        )
    return out


POINTS: dict[str, dict] = {
    "n5-wa": {
        "orderIndex": 45,
        "title": "は",
        "pattern": "は",
        "reading": "は",
        "shortDefinition": "as for; topic marker",
        "headlineEnglish": "as for; topic marker",
        "blurb": "Marks what you're talking about — the topic. Think \"As for X…\" and then say something about it.",
        "structure": "Noun + は + comment\n\n東京は人が多い。\nTokyo has a lot of people.",
        "forms": ["は"],
        "formation": [
            {
                "title": "Noun + は",
                "body": "Place は after the word you want to talk about.\n\nお昼はパンを食べる。\nFor lunch, I eat bread.",
            }
        ],
        "usage": [
            {
                "title": "Topic, not subject",
                "body": "は frames the sentence. What follows describes that topic — not always the doer of an action.",
            },
            {
                "title": "Compared to が",
                "body": "が spotlights who acts (猫が来た). は keeps talking about something already on the table (猫は小さい).",
            },
        ],
        "relatedPointIDs": ["n5-ga-1"],
        "examples": [
            ex("東京は人が多い。", "toukyou wa hito ga ooi.", "Tokyo has a lot of people.", "は"),
            ex("お昼はパンを食べる。", "ohiru wa pan o taberu.", "For lunch, I eat bread.", "は"),
            ex("私は猫が好きです。", "watashi wa neko ga suki desu.", "I like cats.", "は"),
            ex("ここは静かだね。", "koko wa shizuka da ne.", "It's quiet here, isn't it?", "は"),
            ex("日本語は難しいですか。", "nihongo wa muzukashii desu ka.", "Is Japanese difficult?", "は"),
        ],
        "drills": [
            {
                "kind": "precursorChoice",
                "instruction": "Select the correct particle.",
                "exampleJapanese": "これ___本です。",
                "targetSubstring": "は",
                "english": "This is a book.",
                "choices": ["は", "が", "を", "に"],
                "correctChoice": "は",
            },
            {
                "kind": "contrastChoice",
                "contrastLabel": "Topic vs. subject",
                "choices": ["私は行きます", "私が行きます"],
                "correctChoice": "私は行きます",
            },
        ],
    },
    "n5-ga-1": {
        "orderIndex": 4,
        "title": "が①",
        "pattern": "が①",
        "reading": "が",
        "shortDefinition": "subject marker; who or what acts",
        "headlineEnglish": "subject marker; identifies who or what acts",
        "blurb": "Marks the doer — who or what performs the action. Often answers 誰が or 何が.",
        "structure": "Noun + が + predicate\n\n星が見える。\nYou can see stars.",
        "register": "casual",
        "forms": ["が"],
        "formation": [
            {
                "title": "Noun + が",
                "body": "Attach が to the noun that performs the verb.\n\n兄が来た。\nMy older brother came.",
            },
            {
                "title": "Answering 誰が・何が",
                "body": "Questions with 誰が or 何が take が in the answer.\n\n誰が来た？ → 友達が来た。",
            },
        ],
        "usage": [
            {
                "title": "New information",
                "body": "Use が when you identify someone or something for the first time. Once they're on the table, は often takes over.",
            },
        ],
        "usageLadders": [
            {
                "label": "someone arrived",
                "levels": [
                    {"japanese": "友達が来た", "register": "Casual"},
                    {"japanese": "友達が来ました", "register": "Polite"},
                ],
            },
        ],
        "relatedPointIDs": ["n5-wa", "n5-ga-iru"],
        "examples": [
            ex("星が見える。", "hoshi ga mieru.", "You can see stars.", "が"),
            ex("お腹が空いた。", "onaka ga suita.", "I'm hungry.", "が"),
            ex("誰が来た？兄が来た。", "dare ga kita? ani ga kita.", "Who came? My brother came.", "が"),
            ex("音楽が好きだ。", "ongaku ga suki da.", "I like music.", "が"),
            ex("問題がある。", "mondai ga aru.", "There is a problem.", "が"),
        ],
        "drills": [
            {
                "kind": "precursorChoice",
                "instruction": "Select the correct particle.",
                "exampleJapanese": "雨___降る。",
                "targetSubstring": "が",
                "english": "It is raining.",
                "choices": ["が", "は", "を", "に"],
                "correctChoice": "が",
            },
            {
                "kind": "contrastChoice",
                "contrastLabel": "Identifying who did it vs. stating a topic",
                "choices": ["私が行きます", "私は行きます"],
                "correctChoice": "私が行きます",
            },
        ],
    },
    "n5-ga-2": {
        "orderIndex": 5,
        "title": "が②",
        "pattern": "が②",
        "reading": "が",
        "shortDefinition": "but; however",
        "headlineEnglish": "but; however",
        "blurb": "Between two ideas, が means \"but\" — a touch more formal than けど.",
        "structure": "Clause + が + clause\n\n忙しいが、楽しみだ。\nI'm busy, but I'm looking forward to it.",
        "forms": ["が"],
        "formation": [
            {
                "title": "Clause + が + clause",
                "body": "Link contrasting ideas with が.\n\n遠いが、行きたい。\nIt's far, but I want to go.",
            }
        ],
        "usage": [
            {
                "title": "Soft contrast",
                "body": "The first part admits a downside; the second part is what you really want to say.",
            }
        ],
        "relatedPointIDs": ["n5-ga-1", "n5-kedo"],
        "examples": [
            ex("難しいが、楽しい。", "muzukashii ga, tanoshii.", "It's difficult, but fun.", "が"),
            ex("忙しいが、楽しみだ。", "isogashii ga, tanoshimi da.", "I'm busy, but I'm looking forward to it.", "が"),
            ex("遠いが、行きたい。", "tooi ga, ikitai.", "It's far, but I want to go.", "が"),
            ex("高いが、買う。", "takai ga, kau.", "It's expensive, but I'll buy it.", "が"),
            ex("雨だが、出かける。", "ame da ga, dekakeru.", "It's raining, but I'm heading out.", "が"),
        ],
        "drills": [
            {
                "kind": "meaningChoice",
                "exampleJapanese": "難しいが、楽しい。",
                "choices": [
                    "It's difficult, but fun.",
                    "It's difficult and fun.",
                    "It's difficult, so it's fun.",
                    "It's difficult, isn't it fun?",
                ],
                "correctChoice": "It's difficult, but fun.",
            },
            {
                "kind": "sentenceChoice",
                "prompt": "It's expensive, but I'll buy it.",
                "choices": [
                    "高いが、買う。",
                    "高いから、買う。",
                    "高いけど、買わない。",
                    "高いは、買う。",
                ],
                "correctChoice": "高いが、買う。",
            },
        ],
    },
    "n5-ka-1": {
        "orderIndex": 6,
        "title": "か①",
        "pattern": "か①",
        "reading": "か",
        "shortDefinition": "or (between two options)",
        "headlineEnglish": "or (choice between two options)",
        "blurb": "Between two nouns, か means \"or\" — pick one.",
        "structure": "A + か + B\n\nラーメンかうどん？\nRamen or udon?",
        "forms": ["か"],
        "formation": [
            {
                "title": "A + か + B",
                "body": "Put か between the options.\n\n赤か青？\nRed or blue?",
            }
        ],
        "usage": [
            {
                "title": "Offering a choice",
                "body": "Present alternatives and let the listener choose. Often casual — no です needed.",
            }
        ],
        "relatedPointIDs": ["n5-ka-2"],
        "examples": [
            ex("ラーメンかうどん？", "raamen ka udon?", "Ramen or udon?", "か"),
            ex("赤か青？", "aka ka ao?", "Red or blue?", "か"),
            ex("週末か来週？", "shuumatsu ka raishuu?", "This weekend or next week?", "か"),
            ex("ビールかワイン？", "biiru ka wain?", "Beer or wine?", "か"),
            ex("歩くか走る？", "aruku ka hashiru?", "Walk or run?", "か"),
        ],
        "drills": [
            {
                "kind": "meaningChoice",
                "exampleJapanese": "ラーメンかうどん？",
                "choices": [
                    "Ramen or udon?",
                    "Is it ramen?",
                    "Ramen and udon.",
                    "Ramen because of udon.",
                ],
                "correctChoice": "Ramen or udon?",
            },
        ],
    },
    "n5-ka-2": {
        "orderIndex": 7,
        "title": "か②",
        "pattern": "か②",
        "reading": "か",
        "shortDefinition": "question particle",
        "headlineEnglish": "question particle",
        "blurb": "At the end of a sentence, か turns a statement into a yes/no question.",
        "structure": "Statement + か\n\n分かりますか。\nDo you understand?",
        "forms": ["か"],
        "formation": [
            {
                "title": "Statement + か",
                "body": "Add か to ask yes/no.\n\n行きますか。\nWill you go?",
            },
            {
                "title": "Polite questions",
                "body": "With です or ます → ですか / ますか.\n\n大丈夫ですか。\nAre you okay?",
            },
        ],
        "usage": [
            {
                "title": "Yes/no questions",
                "body": "か asks whether something is true. Answer with はい, いいえ, or a fuller reply.",
            }
        ],
        "relatedPointIDs": ["n5-ka-1"],
        "examples": [
            ex("分かりますか。", "wakarimasu ka.", "Do you understand?", "か"),
            ex("もう帰りますか。", "mou kaerimasu ka.", "Are you leaving already?", "か"),
            ex("これ、あなたのですか。", "kore, anata no desu ka.", "Is this yours?", "か"),
            ex("寒いですか。", "samui desu ka.", "Is it cold?", "か"),
            ex("結構ですか。", "kekkou desu ka.", "Is that enough?", "か"),
        ],
        "drills": [
            {
                "kind": "meaningChoice",
                "exampleJapanese": "分かりますか。",
                "choices": [
                    "Do you understand?",
                    "I understand.",
                    "Please understand.",
                    "Understanding is difficult.",
                ],
                "correctChoice": "Do you understand?",
            },
        ],
    },
    "n5-ni": {
        "orderIndex": 36,
        "title": "に",
        "pattern": "に",
        "reading": "に",
        "shortDefinition": "in; at; to; on (time/place/target)",
        "headlineEnglish": "in; at; to; for (location/time)",
        "blurb": "Pins a time, destination, or target — when, where to, or to whom.",
        "structure": "Time/place/person + に\n\n三時に会う。\nMeet at three o'clock.",
        "forms": ["に"],
        "formation": [
            {
                "title": "Destination",
                "body": "Place + に + movement verb\n\n医者に行く。\nGo to the doctor.",
            },
            {
                "title": "Time",
                "body": "Clock time + に\n\n毎朝六時に起きる。\nWake up at six every morning.",
            },
            {
                "title": "Target",
                "body": "Person + に + give/say/call\n\n彼に借りる。\nBorrow from him.",
            },
        ],
        "usage": [
            {
                "title": "に vs. で",
                "body": "に = destination or point in time. で = where an action happens (レストランで食べる).",
            }
        ],
        "relatedPointIDs": ["n5-ni-e", "n5-de-1"],
        "examples": [
            ex("三時に会う。", "sanji ni au.", "Meet at three o'clock.", "に"),
            ex("医者に行く。", "isha ni iku.", "Go to the doctor.", "に"),
            ex("彼に借りる。", "kare ni kariru.", "Borrow from him.", "に"),
            ex("机の上に本がある。", "tsukue no ue ni hon ga aru.", "There is a book on the desk.", "に"),
            ex("毎朝六時に起きる。", "maiasa rokuji ni okiru.", "Wake up at six every morning.", "に"),
        ],
        "drills": [
            {
                "kind": "precursorChoice",
                "instruction": "Select the correct particle.",
                "exampleJapanese": "学校___行く。",
                "targetSubstring": "に",
                "english": "Go to school.",
                "choices": ["に", "で", "を", "は"],
                "correctChoice": "に",
            },
        ],
    },
    "n5-ni-e": {
        "orderIndex": 35,
        "title": "に・へ",
        "pattern": "に・へ",
        "reading": "に",
        "shortDefinition": "to; toward (direction)",
        "headlineEnglish": "to (direction/destination)",
        "blurb": "Both mark direction toward a place. に is everyday; へ sounds a bit more written or directional.",
        "structure": "Place + に / へ + go/head\n\n空港へ向かう。\nHead for the airport.",
        "forms": ["に", "へ"],
        "formation": [
            {
                "title": "Movement toward",
                "body": "Either particle works with 行く, 向かう, 進む.\n\n北に進む。 / 北へ進む。",
            }
        ],
        "usage": [
            {
                "title": "に vs. へ",
                "body": "For most destinations they're interchangeable with 行く. へ emphasizes \"toward\" — common on signs and in writing.",
            }
        ],
        "relatedPointIDs": ["n5-ni"],
        "examples": [
            ex("空港へ向かう。", "kuukou e mukau.", "Head for the airport.", "へ"),
            ex("右へ曲がる。", "migi e magaru.", "Turn right.", "へ"),
            ex("彼の家へ行った。", "kare no ie e itta.", "I went to his house.", "へ"),
            ex("駅に行く。", "eki ni iku.", "Go to the station.", "に"),
            ex("先生のところへ行く。", "sensei no tokoro e iku.", "Go to the teacher's place.", "へ"),
        ],
        "drills": [
            {
                "kind": "sentenceChoice",
                "prompt": "Head for the airport.",
                "choices": [
                    "空港へ向かう。",
                    "空港で向かう。",
                    "空港を向かう。",
                    "空港は向かう。",
                ],
                "correctChoice": "空港へ向かう。",
            },
        ],
    },
    "n5-de-1": {
        "orderIndex": 22,
        "title": "で①",
        "pattern": "で①",
        "reading": "で",
        "shortDefinition": "at; in (place of action)",
        "headlineEnglish": "at; in (location of action)",
        "blurb": "Marks where an action happens — not where you're headed (that's に).",
        "structure": "Place + で + action\n\n図書館で本を読む。\nRead a book at the library.",
        "forms": ["で"],
        "formation": [
            {
                "title": "Place + で + verb",
                "body": "Attach で to the location of the action.\n\n海で泳ぐ。\nSwim at the sea.",
            }
        ],
        "usage": [
            {
                "title": "Stage vs. destination",
                "body": "駅に行く = go to the station. 駅で待つ = wait at the station.",
            }
        ],
        "relatedPointIDs": ["n5-ni", "n5-de-2"],
        "examples": [
            ex("レストランで会う。", "resutoran de au.", "Meet at a restaurant.", "で"),
            ex("図書館で本を読む。", "toshokan de hon o yomu.", "Read a book at the library.", "で"),
            ex("台所で料理する。", "daidokoro de ryouri suru.", "Cook in the kitchen.", "で"),
            ex("海で泳ぐ。", "umi de oyogu.", "Swim in the ocean.", "で"),
            ex("オフィスで働く。", "ofisu de hataraku.", "Work at the office.", "で"),
        ],
        "drills": [
            {
                "kind": "precursorChoice",
                "instruction": "Select the correct particle.",
                "exampleJapanese": "学校___勉強する。",
                "targetSubstring": "で",
                "english": "Study at school.",
                "choices": ["で", "に", "を", "は"],
                "correctChoice": "で",
            },
            {
                "kind": "contrastChoice",
                "contrastLabel": "Destination vs. place of action",
                "choices": ["学校に行く", "学校で勉強する"],
                "correctChoice": "学校で勉強する",
            },
        ],
    },
    "n5-de-2": {
        "orderIndex": 23,
        "title": "で②",
        "pattern": "で②",
        "reading": "で",
        "shortDefinition": "with; by (means or tool)",
        "headlineEnglish": "with; by (means or method)",
        "blurb": "Marks the tool, vehicle, or method — how you do something.",
        "structure": "Means + で\n\nペンで書く。\nWrite with a pen.",
        "forms": ["で"],
        "formation": [
            {
                "title": "Means + で",
                "body": "Put で after the tool or method.\n\n自転車で来た。\nI came by bicycle.",
            }
        ],
        "usage": [
            {
                "title": "How or with what",
                "body": "Answers \"by what means?\" — bus, chopsticks, Japanese, email.",
            }
        ],
        "relatedPointIDs": ["n5-de-1"],
        "examples": [
            ex("ペンで書く。", "pen de kaku.", "Write with a pen.", "で"),
            ex("自転車で来た。", "jitensha de kita.", "I came by bicycle.", "で"),
            ex("ネットで買う。", "netto de kau.", "Buy online.", "で"),
            ex("左手で持つ。", "hidari te de motsu.", "Hold it in your left hand.", "で"),
            ex("英語でメールを書く。", "eigo de meeru o kaku.", "Write an email in English.", "で"),
        ],
        "drills": [
            {
                "kind": "meaningChoice",
                "exampleJapanese": "自転車で来た。",
                "choices": [
                    "I came by bicycle.",
                    "I came to the bicycle.",
                    "I came at the bicycle.",
                    "I came from the bicycle.",
                ],
                "correctChoice": "I came by bicycle.",
            },
        ],
    },
    "n5-mo": {
        "orderIndex": 51,
        "title": "も",
        "pattern": "も",
        "reading": "も",
        "shortDefinition": "also; too; as well",
        "headlineEnglish": "also; too; as well",
        "blurb": "Adds \"also\" or \"too\" — includes something in what was already mentioned.",
        "structure": "Noun + も\n\n田中さんも来る。\nTanaka is coming too.",
        "forms": ["も"],
        "formation": [
            {
                "title": "Noun + も",
                "body": "Swap は or が for も to add \"also.\"\n\n犬も好き。\nI like dogs too.",
            }
        ],
        "usage": [
            {
                "title": "Adding to the set",
                "body": "も layers on: 猫が好き。犬も好き。 = I like cats. I like dogs too.",
            }
        ],
        "relatedPointIDs": ["n5-wa"],
        "examples": [
            ex("田中さんも来る。", "tanaka san mo kuru.", "Tanaka is coming too.", "も"),
            ex("土曜日も開いてる。", "doyoubi mo aiteru.", "They're open on Saturdays too.", "も"),
            ex("水も飲む。", "mizu mo nomu.", "I'll drink water too.", "も"),
            ex("子どもも泣いてる。", "kodomo mo naiteru.", "The child is crying too.", "も"),
            ex("こちらもどうぞ。", "kochira mo douzo.", "This for you as well.", "も"),
        ],
        "drills": [
            {
                "kind": "meaningChoice",
                "exampleJapanese": "田中さんも来る。",
                "choices": [
                    "Tanaka is coming too.",
                    "Tanaka is coming. (topic)",
                    "Only Tanaka is coming.",
                    "Tanaka is not coming.",
                ],
                "correctChoice": "Tanaka is coming too.",
            },
        ],
    },
}


def finalize_point(point_id: str, body: dict) -> dict:
    point = {"id": point_id, "usageLadders": [], "status": "draft", **body}
    point.setdefault("drills", [])
    point["contrastDrills"] = contrast_drills_from(point)
    return point


def main() -> None:
    finalized = {pid: finalize_point(pid, POINTS[pid]) for pid in CHECKPOINT1_IDS}

    for pid, point in finalized.items():
        path = POINTS_DIR / f"{pid}.json"
        path.write_text(json.dumps(point, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    bundle = json.loads(GRAMMAR_JSON.read_text(encoding="utf-8"))
    by_id = {p["id"]: p for p in bundle["points"]}
    for pid in CHECKPOINT1_IDS:
        by_id[pid] = finalized[pid]
    bundle["formatVersion"] = 2
    bundle["points"] = sorted(by_id.values(), key=lambda p: (p.get("orderIndex", 0), p.get("id", "")))
    GRAMMAR_JSON.write_text(json.dumps(bundle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Wrote {len(CHECKPOINT1_IDS)} checkpoint-1 points to {POINTS_DIR}")
    print(f"Updated bundle → {GRAMMAR_JSON}")


if __name__ == "__main__":
    main()
