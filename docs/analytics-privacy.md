# Analytics & privacy (PostHog)

Shizen sends a small set of funnel events (onboarding → paywall → purchase) to PostHog.
All of it goes through `shizen/App/Analytics.swift`; no other file imports PostHog.

## What is never collected

- No IDFA. The app doesn't link AdSupport or AppTrackingTransparency and never shows the ATT prompt.
- No session replay, no screen autocapture, no tap/element autocapture.
- No email, name, or other profile fields. Identity is the Firebase uid only.
- No data is shared with data brokers or used for third-party advertising.

## Events

| Event | When | Properties |
| --- | --- | --- |
| `onboarding_step_viewed` | Each time an onboarding screen appears (fired by `OnboardingCoordinator`) | `step_index` (Int), `step_name` (stable snake_case id, e.g. `intro`, `level`, `team_note`), `flow` (`natural`, `listen_first`, `tutor`, `original`, `journey`) |
| `onboarding_completed` | Onboarding finishes | `flow` |
| `paywall_viewed` | Each appearance of the feature-carousel paywall | `variant` (`feature_carousel`), `offering_id`, `source` (e.g. `onboarding`) |
| `trial_started` | A RevenueCat entitlement becomes active in a trial period (`PurchaseAnalytics`) | `product_id`, `package_id`, `period`, `price`, `currency` |
| `purchased` | A RevenueCat entitlement becomes active as paid, or a trial converts | same as `trial_started` |
| `Application Installed` / `Updated` / `Opened` / `Backgrounded` | PostHog SDK lifecycle events | build, version, `from_background` |

### Lessons

All carry `lesson_type` (`dialogue`, `grammar`, `kana`) and `lesson_id` (scene id, grammar point id, or kana row id).

| Event | When | Extra properties |
| --- | --- | --- |
| `lesson_started` | A scene / grammar / kana session opens | dialogue: `collection_id`, `session_mode` (`attempt`, `view_lesson`, `retake_quiz`), `source` (`home`, `picker`); kana: `kana_session` |
| `dialogue_listened` | First full listen of a dialogue scene | `hardcore`, `seconds` |
| `quiz_started` | The quiz page is first reached | — |
| `quiz_completed` | Quiz finished | `correct_count`, `question_count`, `star_count`, `points`, `english_peeked_count`, `hardcore`, `seconds` |
| `highlights_viewed` | Highlights page first reached | — |
| `lesson_completed` | Scene finished (quiz done, or dialogue done when there's no quiz); grammar/kana summary reached | dialogue: quiz properties; grammar/kana: `correct_count`, `wrong_count`, `best_streak`, `lives_remaining`, `seconds` |
| `lesson_failed` | Grammar/kana: out of lives | same as grammar/kana `lesson_completed` |
| `lesson_abandoned` | Left before finishing | `furthest_stage` (`dialogue`, `listened`, `quiz`, `drills`), `seconds` |

### Interactions

| Event | When | Properties |
| --- | --- | --- |
| `sentence_breakdown_opened` | A dialogue line's breakdown screen opens | `source` (`dialogue`, `scripted`, `other`) |
| `sentence_breakdown_closed` | Breakdown screen closes (one summary per visit) | `tokens_viewed` (count of distinct words), `spans_viewed`, `nuance_opened`, `sentence_plays`, `opened_repeat_after_me`, `seconds`, `source` |
| `gloss_viewed` | Multi-word span selected, or nuance card opened | `kind` (`multi_token`, `nuance`), `token_count`, `source` |
| `word_detail_opened` | Dictionary detail for a word | `from_sentence` |
| `kanji_detail_opened` | Kanji detail screen | — |
| `dictionary_result_opened` | A dictionary search result is tapped (the search text is never sent) | `result_rank` |
| `flashcard_added` | Word or phrase saved to a folder | `kind` (`word`, `phrase`), `from_lesson` |
| `audio_replayed` | Dialogue played again, restarted, a line jumped to, or a sentence played in a breakdown | `kind` (`dialogue`, `restart`, `line`, `sentence`), `speed`, `lesson_id` |
| `playback_speed_changed` | Dialogue speed changed | `speed`, `lesson_id` |

### Paywall detail (feature-carousel variant)

All carry `variant`, `offering_id`, `source`, `seconds_on_screen`.

| Event | When | Extra properties |
| --- | --- | --- |
| `paywall_carousel_swiped` | The learner moves the carousel (swipe or page dots; auto-advance isn't sent) | `card`, `card_index`, `from_card`, `direction`, `trigger` |
| `paywall_plan_selected` | A plan tile is tapped | `package_id`, `product_id`, `period`, `price`, `currency`, `has_trial` |
| `paywall_cta_tapped` | Purchase button tapped (intent only) | plan properties + carousel summary |
| `purchase_cancelled` / `purchase_failed` | Store sheet cancelled / errored | plan properties; failed adds `error_domain`, `error_code` |
| `restore_completed` | Restore finished | `result` (`restored`, `nothing`, `failed`) |
| `paywall_dismissed` | Paywall closes | `reason` (`close`, `purchased`, `restored`, `system`) + carousel summary |
| `pro_gate_hit` | A Pro-only feature blocks a free user (no gates exist yet) | `feature` |

Carousel summary: `current_card`, `cards_seen`, `cards_seen_count`, `card_count`, `max_card_index`, `user_swipes`, `page_control_taps`, `auto_advances`, `user_drove_carousel`, `seconds_to_first_swipe`, and `dwell_<card>_s` (seconds each card was on screen).

### Quality

| Event | When | Properties |
| --- | --- | --- |
| `lesson_issue_reported` | Issue report sent | `categories`, `has_note` (the note text is never sent) |
| `lesson_feedback_rated` | Post-quiz ratings sent | `lesson_id`, `rating_<dimension>` (1–5) |
| `llm_feedback` | Thumbs up/down on an AI answer | `feature`, `rating`, `reason` |
| `gateway_request_failed` | An LLM gateway call fails (not cancellations or signed-out) | `endpoint`, `error`, `status`, `url_error_code` |
| `lesson_audio_failed` | A lesson's audio can't be loaded | `remote`, `lesson_id` |

### Person properties

Set on the person profile so any chart can be split by them: `is_pro`, `onboarding_flow`, `level`, `daily_goal_minutes` / `daily_goal`, `register`, `track`, `why_learning` (the onboarding options picked). No free text.

Every event also carries PostHog's default context: app version/build, OS version, device model,
locale, timezone, screen size, and PostHog's anonymous `distinct_id` (a random UUID the SDK
generates and stores on device; it isn't the IDFA or IDFV). PostHog derives coarse location
(country/city) from the IP address at ingestion.

### Identity

- Signed in (Firebase Auth): `identify(<firebase uid>)`. No person properties are set.
- Signed out: `reset()`, which drops the uid and starts a new anonymous id.

### DEBUG builds

Nothing is sent unless the scheme sets `POSTHOG_DEBUG_SEND=1`. When it is set, every event carries
`is_debug = true` so it can be filtered out of the production funnel. Events are always logged to
the Xcode console in DEBUG.

## App Store privacy answers (SHZ-26)

Tracking: **No.** Nothing is linked with third-party data for advertising, and no IDFA is read.

Add these data types (all purpose **Analytics**, **not used for tracking**):

| Data type | Linked to user? | Why |
| --- | --- | --- |
| Identifiers → **User ID** | Yes | Firebase uid sent via `identify` |
| Usage Data → **Product Interaction** | Yes | Onboarding, lesson, interaction, paywall, and lifecycle events; onboarding answers as person properties |
| Diagnostics → **Other Diagnostic Data** | Yes | `gateway_request_failed`, `lesson_audio_failed` |
| Purchases → **Purchase History** | Yes | `trial_started`, `purchased` |
| Identifiers → **Device ID** | Yes | Only if Apple's definition is taken to cover PostHog's anonymous random id; the conservative choice is to declare it |
| Location → **Coarse Location** | Yes | Only if PostHog keeps IP geolocation. Turn on "Discard client IP data" in the PostHog project settings to avoid declaring it |

If RevenueCat's native PostHog integration is enabled later, disable `PurchaseAnalytics` so purchases aren't counted twice; the privacy answers don't change.
