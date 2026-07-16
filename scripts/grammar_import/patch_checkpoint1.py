#!/usr/bin/env python3
"""Patch N5 grammar checkpoint 1 (core particles) with enriched lesson content."""

from __future__ import annotations

import json
from pathlib import Path

GRAMMAR_JSON = Path(__file__).resolve().parents[2] / "shizen/Resources/Grammar/n5.grammar.json"

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


def ex(
    japanese: str,
    romaji: str,
    english: str,
    target: str,
    *,
    setting: str | None = None,
    payoff: str = "A",
    lines: list[dict] | None = None,
) -> dict:
    row: dict = {
        "japanese": japanese,
        "romaji": romaji,
        "english": english,
        "targetSubstring": target,
        "audioKey": None,
    }
    if setting and lines:
        row["scenario"] = {
            "setting": setting,
            "payoffSpeaker": payoff,
            "lines": lines,
        }
    return row


def line(speaker: str, japanese: str, romaji: str, english: str) -> dict:
    return {
        "speaker": speaker,
        "japanese": japanese,
        "romaji": romaji,
        "english": english,
    }


PATCHES: dict[str, dict] = {
    "n5-wa": {
        "blurb": (
            "は marks the topic of your sentence — what you're talking about. "
            "Think of it as setting the stage: \"As for X…\" The rest of the sentence "
            "tells us something about that topic. It doesn't mean \"is\" on its own."
        ),
        "formation": [
            {
                "title": "Noun + は",
                "body": "Place は right after the word you want to talk about.\n\n私は学生です。\nAs for me, (I) am a student.",
            }
        ],
        "usage": [
            {
                "title": "Topic, not subject",
                "body": "は frames what the sentence is about. The verb or adjective that follows describes that topic — not necessarily the doer of an action.",
            },
            {
                "title": "Compared to が",
                "body": "が identifies who or what acts (\"a cat came\"). は picks up a topic you keep talking about (\"the cat is small\").",
            },
        ],
        "relatedPointIDs": ["n5-ga-1"],
        "examples": [
            ex(
                "私は学生です。",
                "watashi wa gakusei desu.",
                "I am a student.",
                "は",
                setting="Two classmates introduce themselves on the first day of school.",
                payoff="A",
                lines=[
                    line("B", "はじめまして。", "hajimemashite.", "Nice to meet you."),
                    line("A", "こちらこそ。", "kochira koso.", "Likewise."),
                ],
            ),
            ex(
                "これは本です。",
                "kore wa hon desu.",
                "This is a book.",
                "は",
                setting="A student holds up something from their bag.",
                payoff="B",
                lines=[
                    line("A", "これ、何？", "kore, nani?", "What is this?"),
                    line("B", "見てみて。", "mite mite.", "Take a look."),
                ],
            ),
            ex(
                "今日は雨です。",
                "kyou wa ame desu.",
                "Today it is rainy.",
                "は",
                setting="Two friends look out the window in the morning.",
                payoff="A",
                lines=[
                    line("B", "外、どう？", "soto, dou?", "How's it outside?"),
                    line("A", "天気、見て。", "tenki, mite.", "Check the weather."),
                ],
            ),
            ex(
                "猫は小さいです。",
                "neko wa chiisai desu.",
                "The cat is small.",
                "は",
                setting="A child points at a kitten in the park.",
                payoff="B",
                lines=[
                    line("A", "あの猫、かわいい。", "ano neko, kawaii.", "That cat is cute."),
                    line("B", "うん、ほんとに。", "un, hontou ni.", "Yeah, really."),
                ],
            ),
            ex(
                "母は料理が好きです。",
                "haha wa ryouri ga suki desu.",
                "My mother likes cooking.",
                "は",
                setting="Someone talks about their family at dinner.",
                payoff="A",
                lines=[
                    line("B", "お母さん、何が好き？", "okaasan, nani ga suki?", "What does your mom like?"),
                    line("A", "うちの母ね…", "uchi no haha ne...", "My mom, well..."),
                ],
            ),
        ],
        "drills": [
            {
                "kind": "precursorChoice",
                "instruction": "Select the correct particle to complete the sentence.",
                "exampleJapanese": "これ___本です。",
                "targetSubstring": "は",
                "english": "This is a book.",
                "choices": ["は", "が", "を", "に"],
                "correctChoice": "は",
            },
            {
                "kind": "meaningChoice",
                "exampleJapanese": "私は学生です。",
                "choices": [
                    "I am a student.",
                    "I want to be a student.",
                    "The student is me. (singling me out)",
                    "A student came.",
                ],
                "correctChoice": "I am a student.",
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
        "blurb": (
            "が marks the subject — who or what does the action. Unlike は, which sets the topic, "
            "が spotlights the doer, often answering \"who?\" or \"what?\" Use it when you're "
            "identifying someone or something for the first time."
        ),
        "formation": [
            {
                "title": "Noun + が + predicate",
                "body": "Attach が directly to the noun that performs the action.\n\n猫がいる。\nThere is a cat.",
            },
            {
                "title": "Answering 誰が・何が questions",
                "body": "When a question asks 誰が (who) or 何が (what), the answer uses が.\n\n誰が来た？ → 友達が来た。\nWho came? → A friend came.",
            },
            {
                "title": "が in subordinate clauses",
                "body": "Inside clauses that describe a noun, が is always used — never は.\n\n母が作った料理\nThe food that Mom made",
            },
        ],
        "usage": [
            {
                "title": "Identifying the subject",
                "body": "が points to exactly who or what performs the verb. It often carries a sense of \"it is X that —\" — highlighting the subject.",
            },
            {
                "title": "New information vs. known topic",
                "body": "Use が when the subject is new or being identified. Once established, は often takes over.\n\n犬が来た。犬は大きい。\nA dog came. The dog is big.",
            },
            {
                "title": "Compared to は",
                "body": "は introduces a topic the listener can follow. が identifies the subject. 私は学生です is a self-introduction; 私が学生です singles you out among others.",
            },
        ],
        "usageLadders": [
            {
                "label": "who arrived",
                "levels": [
                    {"japanese": "友達が来た", "register": "Casual"},
                    {"japanese": "友達が来ました", "register": "Polite"},
                    {"japanese": "先生が来ました", "register": "Formal"},
                ],
            },
            {
                "label": "it is raining",
                "levels": [
                    {"japanese": "雨が降る", "register": "Casual"},
                    {"japanese": "雨が降ります", "register": "Polite"},
                    {"japanese": "雨が降っております", "register": "Formal"},
                ],
            },
            {
                "label": "the phone rings",
                "levels": [
                    {"japanese": "電話が鳴る", "register": "Casual"},
                    {"japanese": "電話が鳴ります", "register": "Polite"},
                    {"japanese": "電話が鳴っております", "register": "Formal"},
                ],
            },
        ],
        "examples": [
            ex(
                "庭に猫がいる。",
                "niwa ni neko ga iru.",
                "There is a cat in the garden.",
                "が",
                setting="Two siblings look out into the yard.",
                payoff="A",
                lines=[
                    line("B", "何かいる？", "nanika iru?", "Is something there?"),
                    line("A", "見て、庭。", "mite, niwa.", "Look — the garden."),
                ],
            ),
            ex(
                "誰が来た？友達が来た。",
                "dare ga kita? tomodachi ga kita.",
                "Who came? A friend came.",
                "が",
                setting="Someone hears the doorbell and asks who is visiting.",
                payoff="B",
                lines=[
                    line("A", "あ、来た。", "a, kita.", "Oh, someone's here."),
                    line("B", "誰？", "dare?", "Who?"),
                ],
            ),
            ex(
                "雨が降る。",
                "ame ga furu.",
                "It is raining.",
                "が",
                setting="Two friends step outside and feel raindrops.",
                payoff="A",
                lines=[
                    line("B", "外、どう？", "soto, dou?", "How's it outside?"),
                    line("A", "雨、見える？", "ame, mieru?", "Can you see the rain?"),
                ],
            ),
            ex(
                "犬が大きい。",
                "inu ga ookii.",
                "The dog is big.",
                "が",
                setting="A child sees a large dog on a walk.",
                payoff="B",
                lines=[
                    line("A", "あの犬、すごい。", "ano inu, sugoi.", "That dog is amazing."),
                    line("B", "ほんと、大きいね。", "hontou, ookii ne.", "Yeah, it's really big."),
                ],
            ),
            ex(
                "電話が鳴る。",
                "denwa ga naru.",
                "The phone is ringing.",
                "が",
                setting="A phone rings while two people are talking.",
                payoff="A",
                lines=[
                    line("B", "何の音？", "nani no oto?", "What's that sound?"),
                    line("A", "ちょっと、電話。", "chotto, denwa.", "Hang on — the phone."),
                ],
            ),
        ],
        "drills": [
            {
                "kind": "precursorChoice",
                "instruction": "Select the correct particle to complete the sentence.",
                "exampleJapanese": "雨___降る。",
                "targetSubstring": "が",
                "english": "It is raining.",
                "choices": ["が", "は", "を", "に"],
                "correctChoice": "が",
            },
            {
                "kind": "formChoice",
                "instruction": "Which sentence correctly identifies who came?",
                "prompt": "A friend came.",
                "choices": [
                    "友達が来た。",
                    "友達は来た。",
                    "友達を来た。",
                    "友達に来た。",
                ],
                "correctChoice": "友達が来た。",
            },
            {
                "kind": "meaningChoice",
                "exampleJapanese": "私が作りました。",
                "choices": [
                    "I made it. (singling out the speaker as the one who did it)",
                    "As for me, I cooked.",
                    "I want to make it.",
                    "Someone made it for me.",
                ],
                "correctChoice": "I made it. (singling out the speaker as the one who did it)",
            },
            {
                "kind": "sentenceBuilder",
                "english": "The phone is ringing.",
                "buildComponents": ["電話が", "鳴る"],
                "choices": ["電話が", "鳴る", "電話は", "鳴った", "電話を", "する"],
                "correctChoice": "電話が鳴る",
            },
            {
                "kind": "contrastChoice",
                "contrastLabel": "Identifying who did it vs. stating a topic",
                "choices": ["私が行きます", "私は行きます"],
                "correctChoice": "私が行きます",
            },
            {
                "kind": "sentenceChoice",
                "prompt": "Who came? — A friend came.",
                "choices": [
                    "誰が来た？友達が来た。",
                    "誰は来た？友達は来た。",
                    "誰を来た？友達を来た。",
                    "誰に来た？友達に来た。",
                ],
                "correctChoice": "誰が来た？友達が来た。",
            },
            {
                "kind": "meaningChoice",
                "exampleJapanese": "母が作った料理",
                "choices": [
                    "The food that Mom made",
                    "Mom wants to cook",
                    "Food was made for Mom",
                    "Mom is cooking now",
                ],
                "correctChoice": "The food that Mom made",
            },
        ],
    },
    "n5-ga-2": {
        "blurb": (
            "When が sits between two adjectives or short clauses, it means \"but\" or \"however.\" "
            "It connects contrasting ideas — a slightly more formal cousin of けど. "
            "Both sides of が describe the same subject."
        ),
        "formation": [
            {
                "title": "Adjective + が + adjective",
                "body": "Link two contrasting descriptions with が between them.\n\n難しいが、楽しい。\nIt's difficult, but fun.",
            }
        ],
        "usage": [
            {
                "title": "Soft contrast",
                "body": "が② acknowledges a downside, then adds a positive (or vice versa). The second part is the main point you want to land on.",
            }
        ],
        "relatedPointIDs": ["n5-ga-1", "n5-kedo"],
        "examples": [
            ex(
                "難しいが、楽しい。",
                "muzukashii ga, tanoshii.",
                "It's difficult, but fun.",
                "が",
                setting="A student talks about their Japanese class.",
                payoff="B",
                lines=[
                    line("A", "日本語、どう？", "nihongo, dou?", "How's Japanese?"),
                    line("B", "うん、まあね。", "un, maa ne.", "Yeah, well..."),
                ],
            ),
            ex(
                "小さいが、かわいい。",
                "chiisai ga, kawaii.",
                "It's small, but cute.",
                "が",
                setting="Two friends look at a tiny puppy.",
                payoff="A",
                lines=[
                    line("B", "ちいさいね。", "chiisai ne.", "It's so small."),
                    line("A", "でも、かわいい。", "demo, kawaii.", "But it's cute."),
                ],
            ),
            ex(
                "高いが、おいしい。",
                "takai ga, oishii.",
                "It's expensive, but delicious.",
                "が",
                setting="Someone tries food at a nice restaurant.",
                payoff="B",
                lines=[
                    line("A", "値段、どう？", "nedan, dou?", "What about the price?"),
                    line("B", "まあ、食べてみて。", "maa, tabete mite.", "Well, try it."),
                ],
            ),
            ex(
                "今日は寒いが、行く。",
                "kyou wa samui ga, iku.",
                "Today is cold, but I'm going.",
                "が",
                setting="A friend hesitates before leaving the house.",
                payoff="A",
                lines=[
                    line("B", "寒いよ、今日。", "samui yo, kyou.", "It's cold today."),
                    line("A", "でも、行かなきゃ。", "demo, ikanakya.", "But I have to go."),
                ],
            ),
            ex(
                "本は古いが、好きだ。",
                "hon wa furui ga, suki da.",
                "The book is old, but I like it.",
                "が",
                setting="Someone shows a worn book they treasure.",
                payoff="B",
                lines=[
                    line("A", "その本、古いね。", "sono hon, furui ne.", "That book is old."),
                    line("B", "うん、でも好き。", "un, demo suki.", "Yeah, but I like it."),
                ],
            ),
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
                "prompt": "It's expensive, but delicious.",
                "choices": [
                    "高いが、おいしい。",
                    "高いから、おいしい。",
                    "高いけど、おいしくない。",
                    "高いは、おいしい。",
                ],
                "correctChoice": "高いが、おいしい。",
            },
        ],
    },
    "n5-ka-1": {
        "blurb": (
            "か between two nouns means \"or\" — you're offering a choice. "
            "It only works when picking between options, not at the end of a question."
        ),
        "formation": [
            {
                "title": "A + か + B",
                "body": "Put か between the two choices.\n\nコーヒーかお茶？\nCoffee or tea?",
            }
        ],
        "usage": [
            {
                "title": "Offering a choice",
                "body": "Use か when presenting two (or more) alternatives. The listener picks one. Often used in casual speech without です.",
            }
        ],
        "relatedPointIDs": ["n5-ka-2"],
        "examples": [
            ex(
                "コーヒーかお茶？",
                "koohii ka ocha?",
                "Coffee or tea?",
                "か",
                setting="A host asks a guest what they'd like to drink.",
                payoff="A",
                lines=[
                    line("B", "何か飲む？", "nanika nomu?", "Want something to drink?"),
                    line("A", "うん、お願い。", "un, onegai.", "Yeah, please."),
                ],
            ),
            ex(
                "これかそれ？",
                "kore ka sore?",
                "This one or that one?",
                "か",
                setting="A shop clerk holds up two items.",
                payoff="B",
                lines=[
                    line("A", "どっちがいい？", "docchi ga ii?", "Which do you prefer?"),
                    line("B", "えっと…", "etto...", "Um..."),
                ],
            ),
            ex(
                "犬か猫？",
                "inu ka neko?",
                "A dog or a cat?",
                "か",
                setting="Two friends talk about pets.",
                payoff="A",
                lines=[
                    line("B", "何が好き？", "nani ga suki?", "What do you like?"),
                    line("A", "うーん…", "uun...", "Hmm..."),
                ],
            ),
            ex(
                "今日か明日？",
                "kyou ka ashita?",
                "Today or tomorrow?",
                "か",
                setting="Friends try to pick a day to meet.",
                payoff="B",
                lines=[
                    line("A", "いつ会う？", "itsu au?", "When should we meet?"),
                    line("B", "来週は？", "raishuu wa?", "How about next week?"),
                ],
            ),
            ex(
                "電車かバス？",
                "densha ka basu?",
                "Train or bus?",
                "か",
                setting="Two travelers decide how to get to the station.",
                payoff="A",
                lines=[
                    line("B", "駅、どう行く？", "eki, dou iku?", "How do we get to the station?"),
                    line("A", "どっちがいい？", "docchi ga ii?", "Which is better?"),
                ],
            ),
        ],
        "drills": [
            {
                "kind": "meaningChoice",
                "exampleJapanese": "コーヒーかお茶？",
                "choices": [
                    "Coffee or tea?",
                    "Is it coffee?",
                    "Coffee and tea.",
                    "Coffee because of tea.",
                ],
                "correctChoice": "Coffee or tea?",
            },
            {
                "kind": "sentenceChoice",
                "prompt": "Train or bus?",
                "choices": [
                    "電車かバス？",
                    "電車はバス？",
                    "電車がバス？",
                    "電車をバス？",
                ],
                "correctChoice": "電車かバス？",
            },
        ],
    },
    "n5-ka-2": {
        "blurb": (
            "か at the end of a sentence turns a statement into a yes/no question. "
            "In polite speech you often add ですか. The question mark in English is optional in Japanese — "
            "か already signals a question."
        ),
        "formation": [
            {
                "title": "Statement + か",
                "body": "Add か to the end of a sentence to ask a yes/no question.\n\n雨ですか。\nIs it raining?",
            },
            {
                "title": "Polite questions",
                "body": "With です or ます, か becomes ですか or ますか.\n\n学生ですか。\nAre you a student?",
            },
        ],
        "usage": [
            {
                "title": "Yes/no questions",
                "body": "か asks whether something is true. The listener answers はい or いいえ (or a fuller response).",
            }
        ],
        "relatedPointIDs": ["n5-ka-1"],
        "examples": [
            ex(
                "雨ですか。",
                "ame desu ka.",
                "Is it raining?",
                "か",
                setting="Someone looks out the window and isn't sure.",
                payoff="A",
                lines=[
                    line("B", "外、見て。", "soto, mite.", "Look outside."),
                    line("A", "あれ、雨？", "are, ame?", "Wait, is that rain?"),
                ],
            ),
            ex(
                "学生ですか。",
                "gakusei desu ka.",
                "Are you a student?",
                "か",
                setting="A new acquaintance asks about someone's job.",
                payoff="B",
                lines=[
                    line("A", "大学に通ってる？", "daigaku ni kayotteru?", "Do you go to university?"),
                    line("B", "え、どうして？", "e, doushite?", "Huh, why?"),
                ],
            ),
            ex(
                "これは本ですか。",
                "kore wa hon desu ka.",
                "Is this a book?",
                "か",
                setting="A teacher holds up an object in class.",
                payoff="A",
                lines=[
                    line("B", "これ、何だと思う？", "kore, nan da to omou?", "What do you think this is?"),
                    line("A", "えっと…", "etto...", "Um..."),
                ],
            ),
            ex(
                "大きいですか。",
                "ookii desu ka.",
                "Is it big?",
                "か",
                setting="A child asks about an animal at the zoo.",
                payoff="B",
                lines=[
                    line("A", "あの犬、すごいね。", "ano inu, sugoi ne.", "That dog is amazing."),
                    line("B", "ほんとに大きい？", "hontou ni ookii?", "Is it really big?"),
                ],
            ),
            ex(
                "今、何時ですか。",
                "ima, nanji desu ka.",
                "What time is it now?",
                "か",
                setting="Someone needs to catch a train.",
                payoff="A",
                lines=[
                    line("B", "電車、もうすぐだ。", "densha, mou sugu da.", "The train's coming soon."),
                    line("A", "今、何時？", "ima, nanji?", "What time is it now?"),
                ],
            ),
        ],
        "drills": [
            {
                "kind": "meaningChoice",
                "exampleJapanese": "雨ですか。",
                "choices": [
                    "Is it raining?",
                    "It is raining.",
                    "It will rain.",
                    "Rain or shine?",
                ],
                "correctChoice": "Is it raining?",
            },
            {
                "kind": "sentenceChoice",
                "prompt": "Are you a student?",
                "choices": [
                    "学生ですか。",
                    "学生です。",
                    "学生か。",
                    "学生がいますか。",
                ],
                "correctChoice": "学生ですか。",
            },
        ],
    },
    "n5-ni": {
        "blurb": (
            "に marks a point in time, a destination, or a target. It answers \"when?\", "
            "\"where to?\", and \"to whom?\" — like pinning something on a map or a calendar."
        ),
        "formation": [
            {
                "title": "Destination: place + に + 行く",
                "body": "Use に with verbs of movement to show where you're headed.\n\n学校に行く。\nTo go to school.",
            },
            {
                "title": "Time: clock time + に",
                "body": "に marks when something happens.\n\n七時に寝る。\nTo sleep at seven o'clock.",
            },
            {
                "title": "Target: person + に",
                "body": "に can mark who receives an action.\n\n友達に電話する。\nTo call a friend.",
            },
        ],
        "usage": [
            {
                "title": "Location vs. action",
                "body": "に marks where something exists (駅にいる) or where you're headed (駅に行く). For where an action takes place, use で instead.",
            }
        ],
        "relatedPointIDs": ["n5-ni-e", "n5-de-1"],
        "examples": [
            ex(
                "学校に行く。",
                "gakkou ni iku.",
                "To go to school.",
                "に",
                setting="A parent asks where a child is headed in the morning.",
                payoff="A",
                lines=[
                    line("B", "どこ行くの？", "doko iku no?", "Where are you going?"),
                    line("A", "もう時間だよ。", "mou jikan da yo.", "It's time already."),
                ],
            ),
            ex(
                "七時に寝る。",
                "shichiji ni neru.",
                "To sleep at seven o'clock.",
                "に",
                setting="A parent reminds a child about bedtime.",
                payoff="B",
                lines=[
                    line("A", "もう寝なさい。", "mou nenasai.", "Go to bed already."),
                    line("B", "まだ早いよ。", "mada hayai yo.", "It's still early."),
                ],
            ),
            ex(
                "家に帰る。",
                "ie ni kaeru.",
                "To go home.",
                "に",
                setting="A student packs up after school.",
                payoff="A",
                lines=[
                    line("B", "もう帰る？", "mou kaeru?", "Heading home already?"),
                    line("A", "うん、もう遅いし。", "un, mou osoi shi.", "Yeah, it's getting late."),
                ],
            ),
            ex(
                "友達に電話する。",
                "tomodachi ni denwa suru.",
                "To call a friend.",
                "に",
                setting="Someone picks up their phone to make a call.",
                payoff="B",
                lines=[
                    line("A", "誰に電話？", "dare ni denwa?", "Who are you calling?"),
                    line("B", "ちょっと待って。", "chotto matte.", "Hold on a sec."),
                ],
            ),
            ex(
                "駅にいる。",
                "eki ni iru.",
                "To be at the station.",
                "に",
                setting="A friend texts to ask where someone is.",
                payoff="A",
                lines=[
                    line("B", "今、どこ？", "ima, doko?", "Where are you now?"),
                    line("A", "もう着いた。", "mou tsuita.", "I already arrived."),
                ],
            ),
        ],
        "drills": [
            {
                "kind": "precursorChoice",
                "instruction": "Select the correct particle to complete the sentence.",
                "exampleJapanese": "学校___行く。",
                "targetSubstring": "に",
                "english": "To go to school.",
                "choices": ["に", "で", "を", "は"],
                "correctChoice": "に",
            },
            {
                "kind": "meaningChoice",
                "exampleJapanese": "七時に寝る。",
                "choices": [
                    "To sleep at seven o'clock.",
                    "To sleep for seven hours.",
                    "To sleep until seven o'clock.",
                    "To sleep because of seven o'clock.",
                ],
                "correctChoice": "To sleep at seven o'clock.",
            },
        ],
    },
    "n5-ni-e": {
        "blurb": (
            "Both に and へ mark direction — where something is headed. "
            "に is more common in everyday speech; へ sounds slightly more literary but means the same thing for destinations."
        ),
        "formation": [
            {
                "title": "Place + に / へ + movement verb",
                "body": "Either particle works before verbs like 行く and 帰る.\n\n駅に行く。駅へ行く。\nTo go to the station.",
            }
        ],
        "usage": [
            {
                "title": "に vs. へ",
                "body": "For most learners, に and へ are interchangeable with 行く. へ adds a sense of \"toward\" and appears more in writing, signs, and announcements.",
            }
        ],
        "relatedPointIDs": ["n5-ni"],
        "examples": [
            ex(
                "駅に行く。駅へ行く。",
                "eki ni iku. eki e iku.",
                "To go to the station. / To go toward the station.",
                "に",
                setting="A teacher explains two ways to say the same thing.",
                payoff="A",
                lines=[
                    line("B", "どっちも同じ？", "docchimo onaji?", "Are both the same?"),
                    line("A", "うん、だいたいね。", "un, daitai ne.", "Yeah, basically."),
                ],
            ),
            ex(
                "学校に行く。学校へ行く。",
                "gakkou ni iku. gakkou e iku.",
                "To go to school.",
                "に",
                setting="A child leaves for school in the morning.",
                payoff="B",
                lines=[
                    line("A", "行ってらっしゃい。", "ittekurasshai.", "Have a good day."),
                    line("B", "行ってきます。", "ittekimasu.", "I'm off."),
                ],
            ),
            ex(
                "家に帰る。家へ帰る。",
                "ie ni kaeru. ie e kaeru.",
                "To go home.",
                "に",
                setting="Someone finishes work and heads out.",
                payoff="A",
                lines=[
                    line("B", "もう帰る？", "mou kaeru?", "Going home already?"),
                    line("A", "うん、疲れた。", "un, tsukareta.", "Yeah, I'm tired."),
                ],
            ),
            ex(
                "公園に行く。公園へ行く。",
                "kouen ni iku. kouen e iku.",
                "To go to the park.",
                "に",
                setting="Friends plan a weekend outing.",
                payoff="B",
                lines=[
                    line("A", "明日、どこ行く？", "ashita, doko iku?", "Where are we going tomorrow?"),
                    line("B", "公園はどう？", "kouen wa dou?", "How about the park?"),
                ],
            ),
            ex(
                "東京に行く。東京へ行く。",
                "toukyou ni iku. toukyou e iku.",
                "To go to Tokyo.",
                "に",
                setting="Someone talks about a trip.",
                payoff="A",
                lines=[
                    line("B", "夏休み、どこ？", "natsuyasumi, doko?", "Where for summer break?"),
                    line("A", "東京に行きたい。", "toukyou ni ikitai.", "I want to go to Tokyo."),
                ],
            ),
        ],
        "drills": [
            {
                "kind": "meaningChoice",
                "exampleJapanese": "駅へ行く。",
                "choices": [
                    "To go to the station.",
                    "To go from the station.",
                    "To go by the station.",
                    "To go at the station.",
                ],
                "correctChoice": "To go to the station.",
            },
            {
                "kind": "sentenceChoice",
                "prompt": "To go to the park.",
                "choices": [
                    "公園に行く。",
                    "公園で行く。",
                    "公園を行く。",
                    "公園は行く。",
                ],
                "correctChoice": "公園に行く。",
            },
        ],
    },
    "n5-de-1": {
        "blurb": (
            "で marks where an action happens — the stage, not the destination. "
            "With 行く you use に (where you're headed); with 食べる or 勉強する you use で (where you do it)."
        ),
        "formation": [
            {
                "title": "Place + で + action verb",
                "body": "Attach で to the location where the action takes place.\n\n学校で勉強する。\nTo study at school.",
            }
        ],
        "usage": [
            {
                "title": "Action location vs. destination",
                "body": "駅に行く = heading to the station. 駅で待つ = waiting at the station. に is the pin on the map you're moving toward; で is the room you're already acting in.",
            }
        ],
        "relatedPointIDs": ["n5-ni", "n5-de-2"],
        "examples": [
            ex(
                "学校で勉強する。",
                "gakkou de benkyou suru.",
                "To study at school.",
                "で",
                setting="A student explains their daily routine.",
                payoff="A",
                lines=[
                    line("B", "どこで勉強するの？", "doko de benkyou suru no?", "Where do you study?"),
                    line("A", "いつも学校で。", "itsumo gakkou de.", "Always at school."),
                ],
            ),
            ex(
                "家で食べる。",
                "ie de taberu.",
                "To eat at home.",
                "で",
                setting="Friends decide where to have dinner.",
                payoff="B",
                lines=[
                    line("A", "外で食べる？", "soto de taberu?", "Eat out?"),
                    line("B", "今日は家でいい。", "kyou wa ie de ii.", "Home is fine today."),
                ],
            ),
            ex(
                "駅で待つ。",
                "eki de matsu.",
                "To wait at the station.",
                "で",
                setting="Two friends plan to meet before a trip.",
                payoff="A",
                lines=[
                    line("B", "どこで会う？", "doko de au?", "Where should we meet?"),
                    line("A", "駅で待ってて。", "eki de mattete.", "Wait at the station."),
                ],
            ),
            ex(
                "公園で遊ぶ。",
                "kouen de asobu.",
                "To play at the park.",
                "で",
                setting="Children talk about what to do after school.",
                payoff="B",
                lines=[
                    line("A", "今日、何する？", "kyou, nani suru?", "What are we doing today?"),
                    line("B", "公園に行こう。", "kouen ni ikou.", "Let's go to the park."),
                ],
            ),
            ex(
                "ここで写真を撮る。",
                "koko de shashin o toru.",
                "To take a photo here.",
                "で",
                setting="Tourists find a good spot for a picture.",
                payoff="A",
                lines=[
                    line("B", "いい景色だね。", "ii keshiki da ne.", "Nice view."),
                    line("A", "写真、撮ろう。", "shashin, torou.", "Let's take a photo."),
                ],
            ),
        ],
        "drills": [
            {
                "kind": "precursorChoice",
                "instruction": "Select the correct particle to complete the sentence.",
                "exampleJapanese": "学校___勉強する。",
                "targetSubstring": "で",
                "english": "To study at school.",
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
        "blurb": (
            "で also marks the tool or means — how you get something done. "
            "Think \"by bus,\" \"with chopsticks,\" or \"in Japanese.\""
        ),
        "formation": [
            {
                "title": "Means + で",
                "body": "Put で after the tool, vehicle, or method.\n\nバスで帰る。\nTo go home by bus.",
            }
        ],
        "usage": [
            {
                "title": "Instrument or method",
                "body": "で answers \"how?\" or \"with what?\" — the bus you ride, the language you speak, the chopsticks you eat with.",
            }
        ],
        "relatedPointIDs": ["n5-de-1"],
        "examples": [
            ex(
                "バスで帰る。",
                "basu de kaeru.",
                "To go home by bus.",
                "で",
                setting="Someone chooses how to get home after school.",
                payoff="A",
                lines=[
                    line("B", "どうやって帰る？", "dou yatte kaeru?", "How are you getting home?"),
                    line("A", "バスで行く。", "basu de iku.", "I'll take the bus."),
                ],
            ),
            ex(
                "電車で行く。",
                "densha de iku.",
                "To go by train.",
                "で",
                setting="Friends plan a day trip.",
                payoff="B",
                lines=[
                    line("A", "車で行く？", "kuruma de iku?", "Go by car?"),
                    line("B", "電車のほうがいい。", "densha no hou ga ii.", "Train is better."),
                ],
            ),
            ex(
                "箸で食べる。",
                "hashi de taberu.",
                "To eat with chopsticks.",
                "で",
                setting="A visitor tries Japanese food for the first time.",
                payoff="A",
                lines=[
                    line("B", "フォークあるよ。", "fooku aru yo.", "There's a fork."),
                    line("A", "箸で食べたい。", "hashi de tabetai.", "I want to use chopsticks."),
                ],
            ),
            ex(
                "日本語で話す。",
                "nihongo de hanasu.",
                "To speak in Japanese.",
                "で",
                setting="A teacher encourages a student during conversation practice.",
                payoff="B",
                lines=[
                    line("A", "英語じゃなくて…", "eigo ja nakute...", "Not in English..."),
                    line("B", "日本語で大丈夫。", "nihongo de daijoubu.", "Japanese is fine."),
                ],
            ),
            ex(
                "車で行く。",
                "kuruma de iku.",
                "To go by car.",
                "で",
                setting="A family plans a weekend drive.",
                payoff="A",
                lines=[
                    line("B", "電車のほうが早いよ。", "densha no hou ga hayai yo.", "The train is faster."),
                    line("A", "でも、車で行こう。", "demo, kuruma de ikou.", "But let's go by car."),
                ],
            ),
        ],
        "drills": [
            {
                "kind": "meaningChoice",
                "exampleJapanese": "バスで帰る。",
                "choices": [
                    "To go home by bus.",
                    "To go home to the bus.",
                    "To go home at the bus.",
                    "To go home from the bus.",
                ],
                "correctChoice": "To go home by bus.",
            },
            {
                "kind": "sentenceChoice",
                "prompt": "To eat with chopsticks.",
                "choices": [
                    "箸で食べる。",
                    "箸に食べる。",
                    "箸を食べる。",
                    "箸は食べる。",
                ],
                "correctChoice": "箸で食べる。",
            },
        ],
    },
    "n5-mo": {
        "blurb": (
            "も means \"also\" or \"too\" — it adds something to the set. "
            "Unlike は, which sets a topic, も layers on: \"this too,\" \"me too,\" \"also at school.\""
        ),
        "formation": [
            {
                "title": "Noun + も",
                "body": "Replace は or が with も to add \"also.\"\n\n私も学生です。\nI am also a student.",
            }
        ],
        "usage": [
            {
                "title": "Adding to a group",
                "body": "も includes the marked item in whatever was already mentioned. 猫が好き。犬も好き。 = I like cats. I like dogs too.",
            }
        ],
        "relatedPointIDs": ["n5-wa"],
        "examples": [
            ex(
                "私も学生です。",
                "watashi mo gakusei desu.",
                "I am also a student.",
                "も",
                setting="Two people discover they go to the same school.",
                payoff="B",
                lines=[
                    line("A", "私、学生なんです。", "watashi, gakusei nan desu.", "I'm a student."),
                    line("B", "え、私も！", "e, watashi mo!", "Oh, me too!"),
                ],
            ),
            ex(
                "猫も好きです。",
                "neko mo suki desu.",
                "I also like cats.",
                "も",
                setting="Friends compare favorite animals.",
                payoff="A",
                lines=[
                    line("B", "犬が好き。", "inu ga suki.", "I like dogs."),
                    line("A", "私は猫も好き。", "watashi wa neko mo suki.", "I like cats too."),
                ],
            ),
            ex(
                "水も飲む。",
                "mizu mo nomu.",
                "I'll drink water too.",
                "も",
                setting="Someone orders drinks for the table.",
                payoff="B",
                lines=[
                    line("A", "お茶、お願い。", "ocha, onegai.", "Tea, please."),
                    line("B", "水もください。", "mizu mo kudasai.", "Water too, please."),
                ],
            ),
            ex(
                "友達も来る。",
                "tomodachi mo kuru.",
                "My friend is coming too.",
                "も",
                setting="Someone clarifies who will join a meetup.",
                payoff="A",
                lines=[
                    line("B", "今日、一人？", "kyou, hitori?", "Just you today?"),
                    line("A", "友達も来るよ。", "tomodachi mo kuru yo.", "A friend is coming too."),
                ],
            ),
            ex(
                "これも大きい。",
                "kore mo ookii.",
                "This one is big too.",
                "も",
                setting="Someone compares two items at a shop.",
                payoff="B",
                lines=[
                    line("A", "それ、大きいね。", "sore, ookii ne.", "That one's big."),
                    line("B", "これも大きい。", "kore mo ookii.", "This one's big too."),
                ],
            ),
        ],
        "drills": [
            {
                "kind": "meaningChoice",
                "exampleJapanese": "私も学生です。",
                "choices": [
                    "I am also a student.",
                    "I am a student. (topic)",
                    "Only I am a student.",
                    "I am not a student.",
                ],
                "correctChoice": "I am also a student.",
            },
            {
                "kind": "sentenceChoice",
                "prompt": "I like cats too.",
                "choices": [
                    "猫も好きです。",
                    "猫は好きです。",
                    "猫が好きです。",
                    "猫を好きです。",
                ],
                "correctChoice": "猫も好きです。",
            },
        ],
    },
}


def apply_patch(point: dict, patch: dict) -> None:
    for key, value in patch.items():
        point[key] = value


def main() -> None:
    data = json.loads(GRAMMAR_JSON.read_text(encoding="utf-8"))
    by_id = {p["id"]: p for p in data["points"]}

    missing = [pid for pid in CHECKPOINT1_IDS if pid not in by_id]
    if missing:
        raise SystemExit(f"Missing point IDs: {missing}")

    for pid in CHECKPOINT1_IDS:
        apply_patch(by_id[pid], PATCHES[pid])

    GRAMMAR_JSON.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Patched {len(CHECKPOINT1_IDS)} checkpoint-1 grammar points → {GRAMMAR_JSON}")


if __name__ == "__main__":
    main()
