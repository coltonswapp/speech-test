# Grammar backfill — mapping summary

Proposed mappings only. Nothing has been written to Studio. Hana reviews and applies.

## Totals

- Collections mapped: **32**
- Total items: **370**
- Orphans: **105**
- Ambiguous: **104**

## Conventions used

- **n5- ids preferred.** `patterns.json` holds two parallel sets of ids for the same patterns (for example `mashou` and `n5-mashou`). Every mapping uses the `n5-` id. Nothing references the unprefixed ids.
- **Ambiguous** means the same pattern occurs on more than one spoken line in the scene. The chosen line is in `sourceSpokenStart/End`, and the other indices are in `note`. Most of these are common particles or copulas (です, か, ね, よ). If one chosen line is good enough, Hana can clear the flag before applying. If a label is a specific phrase that occurs only once (for example 似合ってるわよ), it was not flagged.
- **Casual forms** map to their polite catalog entry, with a note: 〜ない？ → `n5-masen-ka`, 〜(よ)うか → `n5-mashouka`, 〜(よ)う → `n5-mashou`, 〜てね / 〜ないで (requests) → `n5-te-kudasai` / `n5-naide-kudasai`, 〜てる → `n5-te-iru`.
- **Line ranges on orphans.** When an orphan's form is in a spoken line, that line is recorded for reference. The apply script skips orphans, so this has no effect on Studio. Orphans that are not in any spoken line have null indices.
- **No slash-pair labels** were found.
- **Pattern ids as labels.** Some highlights have a pattern id as their label (`n5-nakucha` in airport/gate-change, plus every label in around-the-block's first three scenes). These were mapped normally and flagged in `note`.

## Per collection

| collection | items | orphans | ambiguous |
|---|---:|---:|---:|
| a-local-festival | 24 | 8 | 6 |
| airport | 16 | 2 | 0 |
| around-the-block | 15 | 0 | 12 |
| arrival | 16 | 2 | 4 |
| ashiyu | 0 | 0 | 0 |
| at-library | 0 | 0 | 0 |
| batting-cages | 0 | 0 | 0 |
| building-rules | 8 | 0 | 8 |
| buying-a-bike | 23 | 15 | 1 |
| cooking-together | 0 | 0 | 0 |
| dinner-out | 8 | 3 | 1 |
| dinner-plans | 0 | 0 | 0 |
| english-conversation-class | 0 | 0 | 0 |
| everyone-says-something-different | 0 | 0 | 0 |
| exercise-class | 22 | 3 | 4 |
| family-roots | 0 | 0 | 0 |
| festival-day | 0 | 0 | 0 |
| first-day | 11 | 3 | 2 |
| first-evening | 19 | 8 | 2 |
| first-hello | 3 | 0 | 1 |
| helping-in-the-garden | 8 | 1 | 3 |
| home-setup | 8 | 0 | 8 |
| kaitos-hometown | 0 | 0 | 0 |
| morning-walk | 24 | 5 | 5 |
| n3-work-decision | 35 | 25 | 0 |
| new-neighbor | 20 | 2 | 7 |
| one-offs | 21 | 0 | 19 |
| shopping-and-cooking | 22 | 7 | 4 |
| tea-at-mikas | 6 | 0 | 6 |
| the-house | 18 | 2 | 8 |
| train-station | 25 | 9 | 2 |
| trip-to-the-ball-game | 18 | 10 | 1 |

## Orphans (for Colton)

Format: `collection / scene / label / reason`

- a-local-festival / getting-ready / そんなことないです。 / No catalog match. Suggested: そんなことない — "not at all; that's not true" (modest denial).
- a-local-festival / arriving / 〜気がする / No catalog match. Suggested: 〜気がする — "I feel like ~; I have a feeling ~".
- a-local-festival / arriving / 〜がします / No catalog match. Suggested: 〜がする — "to perceive (smell/sound/taste) ~" (いい匂いがします).
- a-local-festival / arriving / 〜てきた / No catalog match. Suggested: 〜てくる (〜てきた) — "change that has come about / started to ~".
- a-local-festival / a-stall / 〜てみる？ / No catalog match. Suggested: 〜てみる — "try doing ~". Also on spoken lines 6, 7.
- a-local-festival / a-stall / 〜ちゃったね。 / No catalog match. Suggested: 〜ちゃう (〜てしまう) — "end up ~; ~ completely (often with regret)". n5-cha-ikenai is a different pattern.
- a-local-festival / a-stall / 〜じゃない！ / No catalog match by meaning. Suggested: 〜じゃない！(rhetorical) — "isn't it ~!; how ~!" (exclamation/praise). n5-janai-dewa-nai is the negative copula, which this is not.
- a-local-festival / a-quiet-moment / 〜てくれて / No catalog match. Suggested: 〜てくれる — "someone does ~ (for me)".
- airport / taxi-to-airport / お願いします / No catalog match. Suggested: お願いします — "please (polite request set phrase)".
- airport / choosing-airport-food / 〜かな / No catalog match. Suggested: 〜かな — "I wonder ~" (n5-naa is a different particle).
- arrival / finding-grandma / 〜ませんでした / No catalog match. Suggested: 〜ませんでした — polite past negative ("did not ~").
- arrival / in-the-car / 〜ました / No catalog match. Suggested: 〜ました — polite past ("did ~"). Also on spoken line 9.
- buying-a-bike / the-old-bike / 〜てみたいなと思って。 / No catalog match. Suggested: 〜てみたい(な)と思って — "I was thinking I'd like to try ~" (〜てみる + たい + と思う). n5-tai covers only たい.
- buying-a-bike / the-old-bike / 〜てもらって、申し訳ないので / No catalog match. Suggested: 〜てもらう — "have someone do ~ for me" (with 申し訳ない, "sorry for having you ~"). n5-node covers only ので.
- buying-a-bike / the-old-bike / 〜あったはずよ。 / No catalog match. Suggested: 〜はず — "should be; is supposed to be (expectation)".
- buying-a-bike / at-the-shop / どれがいい？ / No catalog match. Suggested: どれがいい？ — "which one is good/do you want?" (どれ = which, of 3+).
- buying-a-bike / at-the-shop / 〜と思いますか？ / No catalog match. Suggested: 〜と思いますか — "do you think ~?" (〜と思う).
- buying-a-bike / at-the-shop / 〜そうね / No catalog match. Suggested: 〜そう — "looks/seems ~" (appearance; 軽そうね).
- buying-a-bike / at-the-shop / 〜てみます / No catalog match. Suggested: 〜てみる — "try doing ~".
- buying-a-bike / deciding-and-paying / 〜わね / No catalog match. Suggested: 〜わ(ね) — feminine sentence-ending わ (soft emphasis), here with ね.
- buying-a-bike / deciding-and-paying / 〜払います / No catalog match. Label is a plain polite verb (払います); suggested: 〜ます — polite non-past verb form.
- buying-a-bike / deciding-and-paying / 〜にさせて / No catalog match. Suggested: 〜にさせて — "let me make it ~" (causative of にする; cf. n5-ni-suru).
- buying-a-bike / deciding-and-paying / 〜ように / No catalog match. Suggested: 〜ように — "so that ~ (purpose/goal)".
- buying-a-bike / first-ride / 〜てみて / No catalog match. Suggested: 〜てみる — "try doing ~". Also on spoken line 1.
- buying-a-bike / first-ride / 〜でいいから / No catalog match. Suggested: 〜でいい — "~ is fine/enough" (ゆっくりでいいから).
- buying-a-bike / first-ride / 〜てきました / No catalog match. Suggested: 〜てくる (〜てきた) — "change that has come about / started to ~".
- buying-a-bike / first-ride / 〜できます / No catalog match, and できます is not literally in any line; line 8 has the potential form 行けます. Suggested: potential form (〜える/〜られる) — "can ~".
- dinner-out / an-old-friends-place / 〜かしら / No catalog match. Suggested: 〜かしら — "I wonder ~" (feminine).
- dinner-out / deciding-what-to-eat / 〜てみる / No catalog match. Suggested: 〜てみる — "try doing ~". Also on spoken line 1 (見てみましょう).
- dinner-out / the-toast / 〜かもしれない / No catalog match. Suggested: 〜かもしれない — "might ~; maybe ~".
- exercise-class / planning / 〜と思います / No catalog match. Suggested: 〜と思います — "I think ~" (〜と思う).
- exercise-class / exercise-class / 〜するわね / No catalog match. Suggested: 〜わ(ね) — feminine sentence-ending わ (soft emphasis), here 紹介するわね.
- exercise-class / heading-home / 〜たら / No catalog match. Suggested: 〜たら — "when/after ~; if ~".
- first-day / new-coworker / 〜たら / No catalog match. Suggested: 〜たら — "when/after ~; if ~".
- first-day / meeting-katio / 〜て、どのくらいですか？ / No catalog match. Suggested: 〜て、どのくらいですか — "how long have you been ~ing?" (どのくらい = how long/how much).
- first-day / sato-lunch-invite / 〜といいです / No catalog match. Suggested: 〜といい — "I hope ~; it would be good if ~".
- first-evening / unpacking / 〜たらいいですか？ / No catalog match. Suggested: 〜たらいいですか — "what/where should I ~?" (asking for advice).
- first-evening / unpacking / 〜でいいわよ / No catalog match. Suggested: 〜でいい — "~ is fine/enough" (その引き出しでいいわよ).
- first-evening / unpacking / 〜のです / Not in any spoken line: explanatory のです (n5-no-desu) does not occur. Line 8 カリフォルニアのです is pronoun の ("the Californian one") + です, closer to n5-no-possessive.
- first-evening / dinner / 〜そうー / No catalog match. Suggested: 〜そう — "looks/seems ~" (appearance). (美味しそうー)
- first-evening / bedtime / 〜そうねー / No catalog match. Suggested: 〜そう — "looks/seems ~" (appearance). (眠そうねー)
- first-evening / bedtime / 〜もんね / No catalog match. Suggested: 〜もん(ね) — "because ~, you know" (casual reason).
- first-evening / bedtime / そうします / No catalog match. Suggested: そうします — "I'll do that" (set phrase; そう + する).
- first-evening / bedtime / 〜と思うわよ / No catalog match. Suggested: 〜と思う — "I think ~" (here with わよ).
- helping-in-the-garden / a-memory-surfaces / 〜てくれる / No catalog match. Suggested: 〜てくれる — "someone does ~ (for me)". Also on spoken line 2 (手伝ってくれたのよ).
- morning-walk / good-morning / よく眠れた？ / No catalog match. Suggested: potential form 〜(ら)れる — "can ~" (よく眠れた？ "did you sleep well?").
- morning-walk / good-morning / 〜もんね / No catalog match. Suggested: 〜もん(ね) — "because ~, you know" (casual reason).
- morning-walk / in-the-park / 〜なんだって / No catalog match. Suggested: 〜んだって — "I heard that ~; they say ~" (hearsay って).
- morning-walk / at-the-conbini / 〜はどこですか？ / No catalog match. Suggested: 〜はどこですか — "where is ~?" (n5-wa-topic and n5-ka-question cover only parts).
- morning-walk / at-the-conbini / 〜わよ。 / No catalog match. Suggested: 〜わ(よ) — feminine sentence-ending わ (soft emphasis), here with よ.
- n3-work-decision / closing-shift / 〜っぱなし / No catalog match. Suggested: 〜っぱなし — "leaving ~ as is; continuously ~". Also on spoken line 5 (立ちっぱなし).
- n3-work-decision / closing-shift / 〜てしまって / No catalog match. Suggested: 〜てしまう — "end up ~; ~ completely (often with regret)". Also on spoken lines 3, 4.
- n3-work-decision / closing-shift / 〜てへんかったん？ / No catalog match. Suggested: 〜へん (Kansai negative) — 取ってへんかったん = 取っていなかったの ("you didn't take ~?"). n5-te-iru covers only the ている part.
- n3-work-decision / closing-shift / 〜たばっかり / No catalog match. Suggested: 〜たばかり (〜たばっかり) — "have just done ~".
- n3-work-decision / something-is-off / 〜し / No catalog match. Suggested: 〜し — "and (what's more); listing reasons". Also on spoken line 11.
- n3-work-decision / something-is-off / 〜ってわけじゃない / No catalog match. Suggested: 〜わけじゃない — "it's not that ~; it doesn't mean ~". Also on spoken line 6.
- n3-work-decision / something-is-off / 〜てくれてありがとう / No catalog match. Suggested: 〜てくれてありがとう — "thanks for ~ing (for me)" (〜てくれる).
- n3-work-decision / whats-actually-going-on / とはいえ、〜 / No catalog match. Suggested: とはいえ — "that said; even so".
- n3-work-decision / whats-actually-going-on / 〜される / No catalog match. Suggested: passive 〜(ら)れる — "be ~ed". (変更される)
- n3-work-decision / whats-actually-going-on / 〜せいで、〜 / No catalog match. Suggested: 〜せいで — "because of ~ (blame)". Also on spoken line 10.
- n3-work-decision / whats-actually-going-on / 〜ばっかり / No catalog match. Suggested: 〜ばかり (〜ばっかり) — "nothing but ~; only ~" (cf. n5-dake, which is neutral "only"). Also on spoken lines 4, 12.
- n3-work-decision / whats-actually-going-on / 〜てもらえてない / No catalog match. Suggested: 〜てもらえる — "be able to have someone ~" (negative: 聞いてもらえてない).
- n3-work-decision / whats-actually-going-on / 〜感じだね / No catalog match. Suggested: 〜感じ — "feels like ~; seems ~". Also on spoken line 3 (入ってる感じで).
- n3-work-decision / is-it-the-job-or-you / 〜みたいやな / No catalog match. Suggested: 〜みたい — "seems like ~; looks like ~". (Kansai やな ending)
- n3-work-decision / is-it-the-job-or-you / 〜わけじゃなくて / No catalog match. Suggested: 〜わけじゃない — "it's not that ~; it doesn't mean ~". Also on spoken lines 9, 11.
- n3-work-decision / is-it-the-job-or-you / 〜気がして / No catalog match. Suggested: 〜気がする — "I feel like ~; I have a feeling ~".
- n3-work-decision / new-neighbor-konbini / 〜の方ですよね / No catalog match. Suggested: 〜の方 (かた) — "the person from ~" (polite "person"); n5-kata is "way of doing", a different 方. Also on spoken line 1.
- n3-work-decision / new-neighbor-konbini / 〜てしまいました / No catalog match. Suggested: 〜てしまう — "end up ~; ~ completely (often with regret)". Also on spoken line 3 (疲れてしまって).
- n3-work-decision / new-neighbor-konbini / 〜みたいですね / No catalog match. Suggested: 〜みたい — "seems like ~; looks like ~".
- n3-work-decision / new-neighbor-konbini / 〜れました / No catalog match. Suggested: passive 〜(ら)れる — "be ~ed". (呼ばれました)
- n3-work-decision / maybe-i-should-quit / 〜ごめん。 / No catalog match. Suggested: ごめん — "sorry" (casual apology; こんな時間にごめん).
- n3-work-decision / maybe-i-should-quit / 〜てさ。 / No catalog match. Suggested: 〜さ — casual sentence-final particle (light emphasis/filler).
- n3-work-decision / maybe-i-should-quit / 〜ことになって。 / No catalog match. Suggested: 〜ことになる — "it ends up that ~; it's been decided that ~".
- n3-work-decision / maybe-i-should-quit / 〜気がする。 / No catalog match. Suggested: 〜気がする — "I feel like ~; I have a feeling ~". Also on spoken line 12.
- n3-work-decision / maybe-i-should-quit / 〜たらええと思う。 / No catalog match. Suggested: 〜たらいい (Kansai 〜たらええ) — "you should ~; it'd be good to ~"; with と思う.
- new-neighbor / who-is-home / 〜で / No catalog match by meaning. Suggested: 〜で (cause/reason) — "because of ~" (アレルギーで). n5-de-location / n5-de-means do not fit.
- new-neighbor / who-is-home / 〜飲む？ / No catalog match. Suggested: plain-form casual question — dictionary form with rising intonation (お茶、飲む？).
- shopping-and-cooking / making-the-list / 〜しか〜ない / No catalog match. Suggested: 〜しか〜ない — "only ~; nothing but ~" (英語しか書けない).
- shopping-and-cooking / at-the-store / 〜でいいですか / No catalog match. Suggested: 〜でいい — "~ is fine/enough". Also on spoken line 7 (それでいいわよ).
- shopping-and-cooking / cooking-together / 〜ちゃいました / No catalog match. Suggested: 〜ちゃう (〜てしまう) — "end up ~; ~ by accident" (落としちゃいました). n5-cha-ikenai is a different pattern.
- shopping-and-cooking / cooking-together / 〜わね / No catalog match. Suggested: 〜わ(ね) — feminine sentence-ending わ (soft emphasis), here with ね. Also on spoken lines 9, 16.
- shopping-and-cooking / cooking-together / 〜てきました / No catalog match. Suggested: 〜てくる (〜てきた) — "change that has come about / started to ~". Also on spoken line 16 (なってきたわね).
- shopping-and-cooking / eating-together / 〜じゃない / No catalog match by meaning. Suggested: 〜じゃない (rhetorical) — "isn't it ~!; you're ~!" (praise: 上手じゃない). n5-janai-dewa-nai is the negative copula, which this is not.
- shopping-and-cooking / eating-together / 〜てくれた / No catalog match. Suggested: 〜てくれる — "someone does ~ (for me)".
- the-house / grandpas-arrival / 〜てやる / No catalog match. Suggested: 〜てやる — "do ~ for someone (casual/downward)" (持ってやろう).
- the-house / emis-room / 〜ておく / No catalog match. Suggested: 〜ておく — "do ~ in advance / for later" (敷いておいた).
- train-station / buying-a-ticket / お〜ください / No catalog match. Suggested: お〜ください — "please ~" (honorific request, e.g. お待ちください). n5-o-go-honorific and n5-te-kudasai each cover only part of it.
- train-station / which-platform / 〜行き (bound for) / No catalog match. Suggested: 〜行き — "bound for ~" (東京行き).
- train-station / which-platform / どこ (where) / No catalog match. Suggested: どこ — "where" (question word).
- train-station / which-platform / 〜て、〜 (sequence) / No catalog match. Suggested: て-form sequence (〜て、〜) — "do A, then B" (cf. n5-te-kara "after doing"). Also on spoken line 4.
- train-station / next-train / 〜時〜分 (telling time) / No catalog match. Suggested: 〜時〜分 — telling time ("~ o'clock, ~ minutes"). Also on spoken line 3 (十時半).
- train-station / missed-train / 〜てしまいました / No catalog match. Suggested: 〜てしまう — "end up ~; ~ (with regret)" (乗り遅れてしまいました).
- train-station / missed-train / 使える (potential) / No catalog match. Suggested: potential form 〜える/〜られる — "can ~" (使えますか).
- train-station / missed-train / お〜いただけます / No catalog match. Suggested: お〜いただけます — "you can ~" (honorific; お乗りいただけます).
- train-station / shinkansen-platform-guidance / お〜ください / No catalog match. Suggested: お〜ください — "please ~" (honorific request, e.g. お待ちください). n5-o-go-honorific and n5-te-kudasai each cover only part of it.
- trip-to-the-ball-game / setup-and-planning / 〜ておく / No catalog match. Suggested: 〜ておく (〜とく) — "do ~ in advance" (連絡しとく).
- trip-to-the-ball-game / arriving-and-scanning-tickets / 〜てよかった / No catalog match. Suggested: 〜てよかった — "I'm glad ~".
- trip-to-the-ball-game / arriving-and-scanning-tickets / 〜てきた / No catalog match. Suggested: 〜てくる (〜てきた) — "change that has come about / started to ~".
- trip-to-the-ball-game / arriving-and-scanning-tickets / 〜じゃん / No catalog match. Suggested: 〜じゃん — "isn't it ~; you know" (casual じゃないか).
- trip-to-the-ball-game / finding-seats-and-beer / 〜てくる / No catalog match. Suggested: 〜てくる — "go and do ~ (and come back)" (買ってくる).
- trip-to-the-ball-game / finding-seats-and-beer / 〜ことにする / No catalog match. Suggested: 〜ことにする — "decide to ~; treat it as ~" (そういうことにしとく).
- trip-to-the-ball-game / kaitos-baseball-history / 〜ちゃう / No catalog match. Suggested: 〜ちゃう (〜てしまう) — "end up ~ (with regret)" (落ちちゃって).
- trip-to-the-ball-game / seventh-inning-stretch / 〜たタイミングで / No catalog match. Suggested: 〜たタイミングで — "at the moment ~".
- trip-to-the-ball-game / seventh-inning-stretch / 〜しかない / No catalog match. Suggested: 〜しかない — "have no choice but to ~".
- trip-to-the-ball-game / heading-home / 〜てよかった / No catalog match. Suggested: 〜てよかった — "I'm glad ~". Also on spoken line 4.
