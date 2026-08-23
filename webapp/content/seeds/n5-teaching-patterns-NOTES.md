# Shizen N5 grammar seed — NOTES

Access date: **2026-08-23**

## Important: no official JLPT list

There is **no official JLPT N5 grammar list** published by JEES/JLPT. Sensei, Japanesetest4you, textbooks, and Shizen’s Coverage library are all curated approximations based on prior exams and pedagogy. Treat band labels as editorial, not canonical.

## Sources

- Primary: [JLPT Sensei — N5 Grammar List](https://jlptsensei.com/jlpt-n5-grammar-list/) (84 patterns, 3 pages: `/`, `/page/2/`, `/page/3/`) — fetched 2026-08-23
- Cross-check: [Japanesetest4you — N5 Grammar List](https://japanesetest4you.com/jlpt-n5-grammar-list/) — fetched 2026-08-23

## Importer schema (CSV)

File: `/workspace/shizen-n5-grammar-seed.csv`

Exact columns (upsert by `id`):

`id,form,gloss,jlptBand,category,status,orderIndex`

- `jlptBand`: always `N5`
- `status`: always `seed`
- `form`: Japanese citation form (was `form_jp`)
- `orderIndex`: 1..n, curriculum-ish (copula → particles → existence → adjectives → conjugation → desire → request/permission → obligation → suggestion → aspect → comparison → time → cause → contrast → quantity → WH → other)
- Romaji, merge groups, and per-row source notes live **only in this NOTES file**, not in the CSV

## Row count

**89** rows in the seed CSV.

Breakdown vs Sensei 84:

- Sensei lessons covered: all 84 surface lessons
- Splits for distinct teaching points: `ga` (subject vs but), `kara` (from vs because), `de` (location vs means)
- Cross-check adds from JT4Y: `n5-no-nominalizer` (の nominalizer), `n5-kurai-gurai` (くらい／ぐらい)
- Net: 84 − 0 + 3 splits extras (ga/kara/de each add +1) + 2 JT4Y = **89**

## Categories used (counts)

- `particle`: 16
- `other`: 9
- `time_sequence`: 9
- `obligation_prohibition`: 6
- `conjugation`: 5
- `contrast`: 5
- `experience_aspect`: 5
- `question_wh`: 5
- `request_permission`: 5
- `suggestion_invitation`: 5
- `comparison`: 4
- `desire`: 4
- `quantity_extent`: 3
- `adjective`: 2
- `cause_reason`: 2
- `copula`: 2
- `existence`: 2

`giving_receiving` is unused in this seed (Sensei does not list あげる／くれる／もらう as N5 grammar lessons; `をください` is filed under `request_permission`).

## Recommended merges for Shizen editors

Editors can collapse rows that share a `merge_group` into one Coverage pattern later. Suggested groups:

- **`nakute-obligation`** (4): `n5-nakute-wa-ikenai`, `n5-nakute-wa-naranai`, `n5-naito-ikenai`, `n5-nakucha`
- **`mashou-family`** (3): `n5-mashou`, `n5-mashouka`, `n5-masen-ka`
- **`no-ga-skill-like`** (3): `n5-no-ga-suki`, `n5-no-ga-jouzu`, `n5-no-ga-heta`
- **`aru-iru`** (2): `n5-ga-arimasu`, `n5-ga-imasu`
- **`connective-and`** (2): `n5-sore-kara`, `n5-soshite`
- **`darou-deshou`** (2): `n5-darou`, `n5-deshou`
- **`de`** (2): `n5-de-location`, `n5-de-means`
- **`demo-shikashi`** (2): `n5-demo`, `n5-shikashi`
- **`ga`** (2): `n5-ga-subject`, `n5-ga-but`
- **`ichiban`** (2): `n5-ichiban`, `n5-no-naka-de-ichiban`
- **`ka`** (2): `n5-ka-question`, `n5-ka-ka-or`
- **`kara`** (2): `n5-kara-from`, `n5-kara-because`
- **`kedo`** (2): `n5-kedo`, `n5-keredo-mo`
- **`mada`** (2): `n5-mada-te-imasen`, `n5-mada`
- **`ni`** (2): `n5-ni-location-time`, `n5-ni-e-direction`
- **`no`** (2): `n5-no-possessive`, `n5-no-nominalizer`
- **`nodesu`** (2): `n5-ndesu`, `n5-no-desu`
- **`temo-ii`** (2): `n5-temo-ii`, `n5-nakutemo-ii`
- **`tewaikenai`** (2): `n5-tewa-ikenai`, `n5-cha-ikenai`
- **`yori-comparison`** (2): `n5-wa-yori-desu`, `n5-yori-hou-ga`
- **`kudasai`** (1): `n5-o-kudasai`

### Merge decision summary

| merge_group | rationale |
| --- | --- |
| `ga` | Same particle, two teaching points (subject marker vs contrastive “but”). Keep separate until product supports multi-sense patterns. |
| `kara` | Same form: ablative “from” vs causal “because”. |
| `de` | Location-of-action vs means/instrument (JT4Y split). |
| `ni` | Core に vs に／へ direction overlap. |
| `no` | Possessive/attributive vs nominalizer. |
| `ka` | Question particle vs か～か “or”. |
| `aru-iru` | あります vs います existence pair. |
| `tewaikenai` | てはいけない + spoken ちゃ／じゃいけない. |
| `nakute-obligation` | なくてはいけない／ならない、ないといけない、なくちゃ. |
| `temo-ii` | てもいい vs なくてもいい (permission / no-need). |
| `mashou-family` | ましょう／ましょうか／ませんか invitation cluster. |
| `yori-comparison` | は〜より・・・です vs より～ほうが. |
| `ichiban` | 一番 vs の中で…が一番. |
| `kedo` | けど vs けれども. |
| `demo-shikashi` | でも vs しかし (connective contrast). |
| `darou-deshou` | Plain vs polite conjecture. |
| `nodesu` | んです vs のです. |
| `no-ga-skill-like` | のが好き／上手／下手 family. |
| `mada` | まだ adverb + まだ～ていません. |
| `connective-and` | それから vs そして. |
| `kudasai` | Soft link for をください (only one member in seed). |

## N4-borderline patterns (flagged)

Keep in N5 seed for Coverage completeness, but mark in product UX / editorial review:

- `n5-hou-ga-ii` — ほうがいい — often taught/tested at N4
- `n5-ta-koto-ga-aru` — たことがある — experience; often N4
- `n5-te-aru` — てある — resulting state; often N4
- `n5-tari-tari` — たり～たり — often N4
- `n5-nakute-wa-naranai` — なくてはならない — formal must; often N4
- `n5-sugiru` — すぎる — too much; often N4
- `n5-tsumori` — つもり — intention; often N4

## Borderline vocabulary kept (Sensei-listed)

Category `other`, not true clause grammar:

- `n5-itsumo` (いつも)
- `n5-totemo` (とても)
- `n5-issho-ni` (一緒に)

## Uncertain / fetch notes

- All three Sensei pages fetched successfully via WebFetch (2026-08-23); total 84 confirmed.
- JT4Y page is a single scroll list (partially image-backed); text extraction covered the main points. **くらい／ぐらい** and **の nominalizer** were clearly in JT4Y text and missing as separate Sensei lessons → added.
- JT4Y also splits **ほうがいい** into affirmative vs negative advice; seed keeps **one** row (`n5-hou-ga-ii`) as a single teaching point.
- JT4Y lists standalone prohibitive **な**; Sensei covers related ground via ないでください／てはいけない — **not** added as a separate row (avoid duplicate prohibition cluster).
- Giving/receiving verbs (あげる／くれる／もらう) absent from Sensei N5 grammar list — **not** invented into seed.
- Romaji spellings follow Sensei’s lesson titles (e.g. `temo ii desu`, `hou ga ii`) for crosswalk stability.

## Product reminder

**Examples in the product should come from real dialogue lines**, not from this seed CSV. This file is Coverage / Pattern metadata only (forms, glosses, bands, categories, sort order).

## Romaji + merge crosswalk

| orderIndex | id | form | romaji | merge_group | source notes |
| ---: | --- | --- | --- | --- | --- |
| 1 | `n5-da-desu` | だ／です | da / desu | — | Sensei #2 |
| 2 | `n5-janai-dewa-nai` | じゃない／ではない | janai / dewa nai | — | Sensei #20; pairs with da/desu |
| 3 | `n5-wa-topic` | は | wa | — | Sensei #79 |
| 4 | `n5-ga-subject` | が | ga | `ga` | Sensei #11 sense A; JT4Y splits subject vs but. |
| 5 | `n5-o-wo` | を | o / wo | — | Sensei #60 |
| 6 | `n5-ni-location-time` | に | ni | `ni` | Sensei #48 primary senses (location/time). |
| 7 | `n5-ni-e-direction` | に／へ | ni / e | `ni` | Sensei #51; overlaps destination sense of に. |
| 8 | `n5-de-location` | で | de | `de` | Sensei #5 sense A; JT4Y splits location vs means. |
| 9 | `n5-de-means` | で | de | `de` | Sensei #5 sense B; JT4Y de-2. |
| 10 | `n5-to-and-with` | と | to | — | Sensei #75 |
| 11 | `n5-mo` | も | mo | — | Sensei #34 |
| 12 | `n5-ya` | や | ya | — | Sensei #82 |
| 13 | `n5-no-possessive` | の | no | `no` | Sensei #52 |
| 14 | `n5-no-nominalizer` | の | no | `no` | JT4Y no-2; not a separate Sensei lesson — cross-check add. |
| 15 | `n5-ne` | ね | ne | — | Sensei #47 |
| 16 | `n5-yo` | よ | yo | — | Sensei #83 |
| 17 | `n5-naa` | なあ／な | naa / na | — | Sensei #37 |
| 18 | `n5-o-go-honorific` | お／ご | o / go | — | Sensei #59 |
| 19 | `n5-ga-arimasu` | があります | ga arimasu | `aru-iru` | Sensei #12 |
| 20 | `n5-ga-imasu` | がいます | ga imasu | `aru-iru` | Sensei #14 |
| 21 | `n5-i-adjectives` | い形容詞 | i-adjectives | — | Sensei #16 |
| 22 | `n5-na-adjectives` | な形容詞 | na-adjectives | — | Sensei #36 |
| 23 | `n5-naru` | なる | naru | — | Sensei #45 |
| 24 | `n5-ni-suru` | にする | ni suru | — | Sensei #50 |
| 25 | `n5-ni-iku` | に行く（にいく） | ni iku | — | Sensei #49 |
| 26 | `n5-kata` | 方（かた） | kata | — | Sensei #24 |
| 27 | `n5-naide` | ないで | naide | — | Sensei #38 |
| 28 | `n5-tai` | たい | tai | — | Sensei #67 |
| 29 | `n5-ga-hoshii` | がほしい | ga hoshii | — | Sensei #13 |
| 30 | `n5-no-ga-suki` | のが好き | no ga suki | `no-ga-skill-like` | Sensei #56 |
| 31 | `n5-tsumori` | つもり | tsumori | — | Sensei #78; often N4-borderline. |
| 32 | `n5-te-kudasai` | てください | te kudasai | — | Sensei #72 |
| 33 | `n5-naide-kudasai` | ないでください | naide kudasai | — | Sensei #39 |
| 34 | `n5-o-kudasai` | をください | o kudasai | `kudasai` | Sensei #61 |
| 35 | `n5-temo-ii` | てもいいです | temo ii desu | `temo-ii` | Sensei #74 |
| 36 | `n5-nakutemo-ii` | なくてもいい | nakutemo ii | `temo-ii` | Sensei #41 |
| 37 | `n5-tewa-ikenai` | てはいけない | te wa ikenai | `tewaikenai` | Sensei #73 |
| 38 | `n5-cha-ikenai` | ちゃいけない／じゃいけない | cha ikenai / ja ikenai | `tewaikenai` | Sensei #1 |
| 39 | `n5-nakute-wa-ikenai` | なくてはいけない | nakute wa ikenai | `nakute-obligation` | Sensei #43 |
| 40 | `n5-nakute-wa-naranai` | なくてはならない | nakute wa naranai | `nakute-obligation` | Sensei #44; often N4-borderline. |
| 41 | `n5-naito-ikenai` | ないといけない | naito ikenai | `nakute-obligation` | Sensei #40 |
| 42 | `n5-nakucha` | なくちゃ | nakucha | `nakute-obligation` | Sensei #42 |
| 43 | `n5-mashou` | ましょう | mashou | `mashou-family` | Sensei #32 |
| 44 | `n5-mashouka` | ましょうか | mashou ka | `mashou-family` | Sensei #33 |
| 45 | `n5-masen-ka` | ませんか | masen ka | `mashou-family` | Sensei #31 |
| 46 | `n5-hou-ga-ii` | ほうがいい | hou ga ii | — | Sensei #15; often N4-borderline. |
| 47 | `n5-wa-dou-desu-ka` | はどうですか | wa dou desu ka | — | Sensei #81 |
| 48 | `n5-te-iru` | ている | te iru | — | Sensei #70 |
| 49 | `n5-te-aru` | てある | te aru | — | Sensei #69; often N4-borderline. |
| 50 | `n5-ta-koto-ga-aru` | たことがある | ta koto ga aru | — | Sensei #66; often N4-borderline. |
| 51 | `n5-mada-te-imasen` | まだ～ていません | mada ~ te imasen | `mada` | Sensei #28 |
| 52 | `n5-tari-tari` | たり～たり | tari ~ tari | — | Sensei #68; often N4-borderline. |
| 53 | `n5-ichiban` | 一番（いちばん） | ichiban | `ichiban` | Sensei #17 |
| 54 | `n5-no-naka-de-ichiban` | の中で［A］が一番 | no naka de [A] ga ichiban | `ichiban` | Sensei #57 |
| 55 | `n5-wa-yori-desu` | は〜より・・・です | wa ~ yori ... desu | `yori-comparison` | Sensei #80 |
| 56 | `n5-yori-hou-ga` | より～ほうが | yori ~ hou ga | `yori-comparison` | Sensei #84 |
| 57 | `n5-mae-ni` | 前に（まえに） | mae ni | — | Sensei #30 |
| 58 | `n5-te-kara` | てから | te kara | — | Sensei #71 |
| 59 | `n5-toki` | とき | toki | — | Sensei #76 |
| 60 | `n5-made` | まで | made | — | Sensei #29 |
| 61 | `n5-kara-from` | から | kara | `kara` | Sensei #23 sense B; JT4Y kara-2. |
| 62 | `n5-sore-kara` | それから | sore kara | `connective-and` | Sensei #63 |
| 63 | `n5-soshite` | そして | soshite | `connective-and` | Sensei #64 |
| 64 | `n5-mada` | まだ | mada | `mada` | Sensei #27 |
| 65 | `n5-mou` | もう | mou | — | Sensei #35 |
| 66 | `n5-kara-because` | から | kara | `kara` | Sensei #23 sense A; JT4Y kara-1. |
| 67 | `n5-node` | ので | node | — | Sensei #58 |
| 68 | `n5-ga-but` | が | ga | `ga` | Sensei #11 sense B; same surface form as subject が. |
| 69 | `n5-demo` | でも | demo | `demo-shikashi` | Sensei #6 |
| 70 | `n5-kedo` | けど | kedo | `kedo` | Sensei #25 |
| 71 | `n5-keredo-mo` | けれども | keredo mo | `kedo` | Sensei #26 |
| 72 | `n5-shikashi` | しかし | shikashi | `demo-shikashi` | Sensei #62 |
| 73 | `n5-dake` | だけ | dake | — | Sensei #3 |
| 74 | `n5-sugiru` | すぎる | sugiru | — | Sensei #65; often N4-borderline. |
| 75 | `n5-kurai-gurai` | くらい／ぐらい | kurai / gurai | — | JT4Y only (not on Sensei 84); cross-check add. |
| 76 | `n5-ka-question` | か | ka | `ka` | Sensei #21 |
| 77 | `n5-ka-ka-or` | か～か | ka ~ ka | `ka` | Sensei #22 |
| 78 | `n5-donna` | どんな | donna | — | Sensei #8 |
| 79 | `n5-doushite` | どうして | doushite | — | Sensei #9 |
| 80 | `n5-douyatte` | どうやって | douyatte | — | Sensei #10 |
| 81 | `n5-darou` | だろう | darou | `darou-deshou` | Sensei #4 |
| 82 | `n5-deshou` | でしょう | deshou | `darou-deshou` | Sensei #7 |
| 83 | `n5-ndesu` | んです | ndesu | `nodesu` | Sensei #46 |
| 84 | `n5-no-desu` | のです | no desu | `nodesu` | Sensei #53 |
| 85 | `n5-no-ga-jouzu` | のが上手（のがじょうず） | no ga jouzu | `no-ga-skill-like` | Sensei #55 |
| 86 | `n5-no-ga-heta` | のが下手（のがへた） | no ga heta | `no-ga-skill-like` | Sensei #54 |
| 87 | `n5-issho-ni` | 一緒に（いっしょに） | issho ni | — | Sensei #18; borderline vocab/phrase. |
| 88 | `n5-itsumo` | いつも | itsumo | — | Sensei #19; borderline vocab (adverb). |
| 89 | `n5-totemo` | とても | totemo | — | Sensei #77; borderline vocab (adverb). |
