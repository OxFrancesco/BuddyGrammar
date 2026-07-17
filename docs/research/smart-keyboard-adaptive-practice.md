# Smarter Keyboard and Adaptive Practice Research

_Research date: 2026-07-16. Scope: touchscreen tap decoding, adaptive practice, correction and prediction, personalization, gesture typing, privacy, and accessibility. Sources are primary research papers, official platform documentation, and official open-source code._

## Executive recommendation

The right model for “I typed `hom`, so make `e` easier to hit” is not to visibly enlarge or move the `e` key. Keep the keyboard visually stable and change the **probability assigned to each nearby key**. At every tap, combine:

1. a spatial likelihood — “given that the user intended `e`, how likely is this touch location?”;
2. a language likelihood — “given `hom`, how likely is `e` next?”; and
3. a guaranteed central **anchor** for every key — a tap near the center of `r` must still produce `r`, even when the language model strongly expects `e`.

This is the source-channel formulation studied for soft keyboards and used in production keyboard decoders. Overly aggressive invisible resizing can make rare words or names impossible to type; anchored targets preserve literal control while retaining most of the error correction benefit. In a Microsoft evaluation, anchored targets improved average keystroke error relative to static targets across standard text, email, query, and URL sets, while avoiding new errors introduced by unanchored resizing.[Gunawardana, Paek, and Meek][s1]

BuddyGrammar should learn **two distinct personal models**:

- a spatial model of where this user actually lands for each key, posture, and orientation;
- a language model of the user’s words, word sequences, languages, and accepted/rejected corrections.

The practice screen should become the safest, highest-quality training source for both. Because the prompt supplies ground truth, a practice session knows what key the user intended even when the touch lands on a neighbor. Normal free typing does not provide such clean labels. The practice curriculum can then target the user’s weak keys and transitions while reserving representative, unseen text to measure whether learning transfers to real typing.

The strongest first experiment is therefore:

> **An adaptive practice sampler plus an anchored probabilistic tap decoder, run in shadow mode before it changes output.**

That creates the data needed for every later improvement without first taking the risk of bad autocorrections.

## Evidence and proposal boundary

- Sections labeled **Evidence** summarize what a cited source demonstrated or what a platform officially exposes.
- Sections labeled **Proposed for BuddyGrammar** are product inferences. They are plausible implementations or experiments, not claims that the cited work directly validated BuddyGrammar’s exact design.
- Reported improvements are not directly comparable across papers: studies differ in keyboard, population, language, task, baseline, and metric.

## Repository starting point

As of this research pass:

- iOS and Android Keyboard Lab screens use a static sample string (`BuddyGrammarIOS/Features/KeyboardLab/KeyboardLabView.swift` and `android/app/src/main/java/com/francescooddo/buddygrammar/ui/BuddyGrammarApp.kt`). They do not yet form a practice curriculum.
- `PersonalLanguageModel.swift` already learns local unigram, bigram, and trigram counts with decay. This is a useful language-personalization seed, but it is not a spatial touch model.
- `SwipeTypingEngine.swift` already uses a SHARK-style blend of location, normalized shape, frequency, and previous-word context. This is a good base for gesture experiments.
- iOS letter entry is currently implemented as one `Button` per letter. That emits the chosen key but not the raw touch point needed to score neighboring keys. A production spatial decoder needs a shared keyboard-surface touch router (or an equivalent custom gesture recognizer) that records a normalized touch location and then decides the key.

## 1. Invisible, context-sensitive hit targets

### Evidence

The classic source-channel decoder selects the intended key by maximizing the product of language and touch probabilities:

\[
k^* = \arg\max_k P_{LM}(k \mid h)\,P_{touch}(z \mid k)
\]

where `h` is typing history and `z` is the touch point. This makes target regions change with context even though visible geometry stays fixed. The Microsoft paper gives the analogous example that after `habi`, part of the visible `y` area may resolve to `t` because `habit` is much more likely than `habiy`.[Gunawardana, Paek, and Meek][s1]

The same paper demonstrates the failure mode: if the language prior dominates, a key’s target can shrink or disappear. It introduces a central anchor that always belongs to its visible key, regardless of context. Its best anchored configuration retained 96% of the corrections made by the unanchored system, recovered 22% of cases where unanchored resizing broke an otherwise-correct static tap, and introduced no new errors in its analysis.[Gunawardana, Paek, and Meek][s1]

Gboard describes the larger production architecture as a spatial model mapping noisy touch or glide points to keys, plus lexicon and language models combined in an FST decoder and searched with beam search. Its earlier Gaussian/rule system was later replaced with a compact neural spatial model; Google reported offline reductions of roughly 15% in bad autocorrections and 10% in wrongly decoded gestures relative to its prior model.[Google Research: Machine Intelligence Behind Gboard][s2]

### Proposed for BuddyGrammar

For a touch at `(x, y)`, first shortlist the nearest keys, then score each:

```text
score(key) = spatialScore(touch | key, user, orientation)
           + λ × characterLanguageScore(key | prefix, previousWords, language)
           + editAndModeAdjustments
```

Use log probabilities in the implementation. `λ` must be tuned and capped; it is a product parameter, not a mathematical constant.

For `hom`:

- the next-character model gives `e` a much higher prior than nearby alternatives;
- a slightly off-center touch near `e`’s edge can therefore resolve to `e`;
- a touch inside another key’s central anchor always remains literal;
- visible key sizes do not change.

Do not discard alternatives immediately. Keep a small per-tap lattice until a word boundary, then decode the most plausible **whole word**. That lets the system reason about insertions, omissions, transpositions, and the full touch sequence rather than greedily locking every ambiguous tap. The literal sequence must remain one candidate, even if it is out of vocabulary.

Suggested confidence policy:

| Calibrated confidence | Behavior |
|---|---|
| Low | Commit literal key; offer a suggestion only if useful. |
| Medium | Let context bias only the ambiguous boundary region; keep the literal word prominent. |
| High, at a word boundary | Auto-correct, temporarily mark the changed word, and provide one-action revert. |
| Inside a key anchor, password/URL/code-like field, or unknown mode | Prefer literal input. |

This separation matters: “bigger `e` hitbox” is a low-level tap decision; replacing a completed word is a higher-risk language decision and should use a stricter threshold.

## 2. Personal spatial touch models

### Evidence

Gboard’s production study found that users rarely touch every key at its geometric center and that offset direction differs by user and key. It adapted Gaussian key centers from local touch statistics and achieved small but statistically significant improvements in typing speed and decoder accuracy across multiple major languages.[Sivek and Riley][s3]

Important implementation details from that study:

- training stayed on device;
- experiments retained only the most recent 250–800 touch points;
- data was stored in coarse, unordered buckets so exact typed sequences could not be reconstructed from the spatial history;
- training used taps from committed words only when the tap-typed word matched the final committed text span;
- adjacent keys could be clustered to reduce overfitting when individual keys lacked data;
- personalized key-center means helped, while full personalized covariance matrices added complexity without further typing-speed or accuracy gains;
- Words Modified Ratio (WMR) and words per minute were used as live quality proxies, rather than pretending that intended text is always observable in free typing.[Sivek and Riley][s3]

The same paper summarizes earlier posture-aware work: touch distributions change with one-thumb versus two-thumb input and while walking. Its own production result still improved without modeling posture, and it identifies portrait/landscape separation as a straightforward next step.[Sivek and Riley][s3]

Modern public touch APIs expose more than a chosen key. `UITouch` documents location, precise location where available, timestamp, touch type, and approximate contact radius.[Apple `UITouch`][s4] Android `MotionEvent` exposes coordinates, time, pressure, size, orientation, and major/minor contact axes, subject to device support.[Android `MotionEvent`][s5] A 2024 Google study found that a full capacitive touch heatmap reduced character error by 21.4% relative to centroid-only input in its experiments and improved speed and satisfaction in a 16-person deployment study.[Lertvittayakumjorn et al.][s6]

### Proposed for BuddyGrammar

Start much simpler than a neural spatial model:

1. Normalize `(x, y)` by the actual key width and height, not screen pixels.
2. Keep per-user sufficient statistics: count, sum of `dx`, sum of `dy`, and optionally squared terms.
3. Begin with one global offset; split into a few adjacent key clusters only after enough evidence; consider per-key means later.
4. Maintain separate maps for portrait/landscape and possibly one-thumb/two-thumb once the data justifies it.
5. Seed every personal model with a strong population prior so the cold-start keyboard behaves normally.
6. Expire old observations or cap the recent history so the keyboard can follow grip, device, injury, and habit changes.

Raw capacitive heatmaps are a research-horizon feature for BuddyGrammar. The reviewed public iOS and Android APIs expose a centroid and coarse contact geometry, not the two-dimensional sensor heatmap used in the 2024 study. Contact radius/major-minor axes, dwell time, approach motion, and recent touch velocity are feasible experiments; full heatmaps should be treated as unavailable to a third-party keyboard unless platform-specific testing proves otherwise.

The most important label rule is: **never learn a key offset simply because the decoder output that key.** That creates a self-reinforcing loop. Learn from:

- ground-truth practice prompts;
- a word the user explicitly selected;
- a tap-typed word that still matches the final text after a short correction window;
- a correction revert, as a strong negative label;
- deletion/retyping only when alignment is unambiguous.

## 3. Adaptive practice that becomes smarter

### Learner-model integration point

The practice curriculum should have its own learner/skill model rather than treating the personal language model as a proxy for mastery. Use a three-loop system:

1. **Observe:** collect privacy-safe evidence from practice attempts and high-confidence real typing outcomes.
2. **Infer:** update small, interpretable skill states with uncertainty and forgetting.
3. **Teach:** choose the next exercise that best balances weakness, review timing, relevance, and coverage.

Keep two families of skills separate because assistance affects their evidence differently:

| Skill family | Examples | Strong evidence | Misleading evidence to avoid |
|---|---|---|---|
| Motor typing | key offsets, `e↔r` confusions, `th` transitions, space/delete timing, swipe turns | a known practice target, an explicit retype, a stable final word with an unambiguous alignment | the decoder's own chosen letter or an autocorrected result |
| Writing knowledge | spelling patterns, articles, tense, agreement, punctuation, register | fresh unaided production, delayed reconstruction, a correction the user accepts and later produces independently | copying visible text, accepting a suggestion, or a hitbox-assisted key |

Bayesian Knowledge Tracing supplies the useful mental model of a hidden mastery state updated by observations.[Corbett and Anderson][s32] Performance Factors Analysis and Learning Factors Analysis show that useful learning estimates can also come from transparent success/failure counts attached to explicit skills.[Pavlik et al.][s33] [Cen et al.][s34] BuddyGrammar should therefore begin with a small PFA/IRT-like model plus forgetting and uncertainty, not a deep knowledge-tracing network whose behavior is hard to inspect on sparse personal data.

Retrieval practice improves long-term retention more than repeated study, and the optimal spacing interval grows with the desired retention interval.[Roediger and Karpicke][s35] [Cepeda et al.][s36] Interleaving can also improve later discrimination even when practice itself feels harder.[Rohrer and Taylor][s37] For BuddyGrammar this implies a progression from support to recall, spaced reappearance of weak skills, and mixed transfer prompts rather than massed repetition of one error.

Represent each skill with compact local state such as:

```text
SkillState {
  skillID, successCount, failureCount, evidenceWeight,
  masteryEstimate, uncertainty, halfLife, lastObservedAt
}

predictedRecall(skill) = 2 ^ (-elapsed / halfLife(skill))
priority(skill) = forgettingRisk * uncertainty
                * realWorldFrequency * userGoalImpact
```

Use an explicit evidence hierarchy when updating it:

- **Strong:** fresh, unaided, delayed, or free-production success; a known motor target; explicit undo/retype evidence.
- **Medium:** cloze, error correction, or reconstruction with limited support.
- **Weak:** copied text, accepted autocorrection, suggestion selection, or a result strongly assisted by the adaptive decoder.
- **Contradictory:** immediate undo, correction revert, or deletion/retyping; preserve this as a negative label instead of averaging it away.

The teaching ladder should gradually remove support: **notice → cloze → correct → reconstruct → free production → mixed transfer**. Controlled exercise-generation research supports selecting or generating text against explicit learning objectives,[Kurdi et al.][s38] but a curated, tagged item bank is the safest first system. Grammar annotation tools such as ERRANT can help normalize error categories, although follow-up work shows that some corrections remain genuinely ambiguous and should not be treated as unquestionable ground truth.[Bryant et al.][s39] [Bryant and Ng][s40]

Personalization is not automatically better instruction: a randomized evaluation of personalized practice found mixed effects rather than a universal gain.[Pane et al.][s41] Measure delayed, unseen transfer at approximately 1, 7, and 28 days, not only accuracy on prompts the scheduler selected. A later contextual bandit can optimize among **pedagogically equivalent** prompt formats or difficulty levels, but it should not decide what constitutes correct language or suppress required coverage. LinUCB is a reasonable interpretable starting point,[Li et al.][s42] with offline policy evaluation before live exploration.[Wang et al.][s43]

Suggested local records are `WritingSignal`, `PracticeAttempt`, `SkillState`, `ItemState`, `LearningProfile`, and `ExperimentEvent`. Store raw practice attempts and private text only on device; sync or analyze derived aggregates only with explicit consent. A practice-generated sentence must update the motor/skill model but must **not** enter the personal language model as if the user had authored it.

### Evidence

The established MacKenzie–Soukoreff evaluation set contains 500 short English phrases, 16–43 characters long, designed to resemble normal English character frequencies; its letter-frequency correlation with the reference corpus was reported as `r = .954`.[MacKenzie: Evaluation of Text Entry Techniques][s7] This supports using representative phrases for baseline and holdout evaluation, not using a single pangram or one repeated sentence.

Gboard’s spatial personalization work exposes why copied practice is especially valuable: in ordinary use the intended key is latent, whereas in a transcription prompt the expected character is known. The production study therefore had to accept only high-confidence committed spans; a practice task can label every tap directly.[Sivek and Riley][s3]

Spaced scheduling is well supported in learning domains, but the most directly useful cited model here is from vocabulary learning, not touchscreen motor learning. Duolingo’s half-life regression predicted recall substantially better than tested baselines and improved engagement in an operational study.[Settles and Meeder][s8] It is evidence that a trainable recency/difficulty schedule can outperform fixed review, but it does **not** prove the same gains for mobile typing.

### Proposed for BuddyGrammar

Treat practice as both a **trainer** and a **calibration laboratory**. Maintain a mastery record for several skill units:

- individual keys;
- neighboring-key confusions, such as `e↔r` or `n↔m`;
- bigram/trigram motor transitions, such as `th`, `ing`, or alternating thumbs;
- space, delete, shift, apostrophe, and punctuation;
- complete words the user repeatedly corrects;
- gesture shapes and turns for swipe typing;
- language-specific diacritics and layout changes.

For each unit, track at least:

```text
attempts, clean successes, substitutions, omissions, insertions,
mean/variance of spatial offset, hesitation, backspace/revert rate,
last practiced time, and an uncertainty/confidence estimate
```

Generate or select each next prompt by balancing four objectives:

1. **Weakness:** include units with high error, hesitation, or uncertainty.
2. **Spacing:** revisit previously difficult units after increasing delays.
3. **Coverage:** prevent the curriculum from collapsing onto a few frequent keys.
4. **Transfer:** keep prompts grammatical and representative of the user’s real language/domain.

An initial, explicitly experimental sampler could allocate roughly 60% of prompt value to weak units, 20% to overdue review, and 20% to representative coverage. The exact weights should be A/B tested rather than treated as evidence-backed constants.

Use three prompt lanes:

| Lane | Purpose | Example source |
|---|---|---|
| Calibration | Dense coverage of uncertain key centers and neighbor pairs. | Short constrained sentences selected for target letters/transitions. |
| Natural transfer | Prevent drill-specific overfitting. | Curated mobile-message and general phrase sets, unseen until evaluation. |
| Personal relevance | Exercise the vocabulary the user actually wants. | Opt-in local words/topics, with sensitive strings filtered and never uploaded. |

Prompt creation can use a constrained generator, but every generated sentence should pass deterministic validation for required letters/transitions, length, language, profanity/safety policy, duplicates, and readability. A curated phrase bank is the reliable fallback. Do not send the personal weakness profile or typed private text to a cloud LLM merely to make practice prose more varied.

Keep training and evaluation separate. Hold back a stable set of unseen representative phrases and report improvement on that holdout, not only on the adaptive prompts the sampler chose. Otherwise the product can appear to improve by repeatedly teaching the test.

Useful learner-facing feedback is concrete and non-punitive:

- “Your `e` taps are consistently 0.14 key-widths to the right; the keyboard adapted.”
- “`r/e` is still uncertain; this round will include more words with both.”
- show accuracy before speed;
- reveal the invisible touch ellipse only in an optional diagnostic view, not during normal typing.

## 4. Whole-word decoding, autocorrection, and post-correction

### Evidence

Google’s FST keyboard decoder composes touch likelihoods, lexicons, probabilistic language models, normalizers, and optional-space/edit paths, then searches the result with beam search. The framework supports literal input, autocorrection, completions, next-word predictions, post-corrections, personalization, and contextualization under mobile memory and latency constraints.[Ouyang et al.][s9]

In a large simulation study, a combined spatial and language model reduced word error from a 38.4% pre-model baseline to 5.7%; adding personal language-model information reduced it further to 4.6% on the study’s Enron-derived setup.[Fowler et al.][s10] These numbers demonstrate the leverage of fusing spatial and linguistic evidence, but they are not expected production gains for BuddyGrammar.

Recent Gboard work uses a neural language model to create a search space that is consumed by the established decoder. In production A/B tests across several languages, this hybrid reduced WMR while increasing decoder latency; the authors emphasize device-tier tradeoffs and propose merging neural and FST candidates instead of immediately replacing a mature decoder end to end.[Google: Neural Search Space in Gboard Decoder][s11]

Apple research found that many users revise before reaching a word boundary and proposed prefix-level error detection/correction to surface recovery earlier.[Bellegarda][s12]

### Proposed for BuddyGrammar

Build a staged decoder instead of one opaque model:

1. **Tap lattice:** top nearby letters and spatial scores for each touch.
2. **Lexical search:** literal word, vocabulary words, personal words, and bounded edit operations.
3. **Context rescoring:** prior word(s), sentence state, active language, and field type.
4. **Decision policy:** literal, suggestion, completion, or autocorrect based on a calibrated score margin.
5. **Post-correction:** retain the previous committed span briefly so the next word can disambiguate it.

Prefix-level intelligence should first be non-destructive: update the suggestion bar or underlined composing text while the user is still typing. Automatic replacement can remain a word-boundary action until live evidence shows that earlier changes reduce total correction cost.

Handle more than substitutions. The candidate search should explicitly model:

- missed and extra touches;
- adjacent transpositions;
- duplicate taps and missed repeated letters;
- omitted apostrophes/diacritics;
- optional or accidental spaces;
- capitalization;
- a literal OOV escape path for names, slang, URLs, code, and multilingual text.

## 5. Prediction without stealing attention

### Evidence

Suggestions are not free. A controlled Google study found that always-present, assertive suggestions reduced the number of actions and were subjectively preferred, but the attention and decision cost impaired average time performance. Probability-gated suggestions were one of the studied strategies.[Quinn and Zhai][s13]

Apple’s iOS 17 keyboard uses an on-device transformer language model, inline word/sentence completions, temporary underlining of autocorrections, and a tap-to-revert affordance. Apple also states that predictions personalize from phrases and words the person uses.[Apple WWDC23 keynote][s14]

### Proposed for BuddyGrammar

- Rank by **expected saved effort**, not probability alone. A long completion with high confidence can be more useful than a trivial one-word prediction.
- Gate the strip when candidates are weak or nearly tied.
- Keep candidate positions stable during a word so the user does not chase moving buttons.
- Separate correction styling from completion/prediction styling.
- Treat a picked suggestion as a positive signal, an immediate backspace/revert as a negative signal, and ignored suggestions as weak/no evidence.
- Offer inline completion only when platform behavior, latency, and accessibility are good; the suggestion bar is the safer initial surface.

The AOSP LatinIME user-history dictionary is a useful concrete reference: its source says it locally gathers typed-word statistics and signals such as autocorrection cancellation and manual picks so the keyboard can adapt over time.[AOSP `UserHistoryDictionary`][s15]

## 6. Personal language, vocabulary, multilingual input, and domain

### Evidence

Federated next-word work showed that recurrent language models can be trained from on-device keyboard data without exporting raw training text and can outperform the compared server-data setup in prediction recall.[Hard et al.][s16] Later Gboard deployments added formal differential privacy guarantees to production next-word models.[Xu et al.][s17]

Vocabulary remains a major failure source. Google describes privacy-preserving discovery of out-of-vocabulary words such as names, emerging terms, unusual capitalization, elongated spellings, and typos; expanding a Spanish vocabulary reduced OOV rate and improved live typing measures in its deployment.[Google: Private Federated Analytics for Gboard][s18]

For morphologically rich languages, fixed word vocabularies are especially limiting. Google’s binding-aware subword framework reported about 20% word-error reduction across studied compounding languages.[Kabel et al.][s19] Gboard’s FST architecture also supports simultaneous language models and transliteration mappings, including optional Latin-to-target-script paths.[Google Research: Machine Intelligence Behind Gboard][s2]

Platform context can help without reading an entire document. Apple’s `UITextDocumentProxy` provides context before and after the cursor, selected text, input mode, and text-input traits.[Apple `UITextDocumentProxy`][s20] Android exposes surrounding text through `InputConnection`, while `EditorInfo` supplies input type, capitalization mode, locale hints, action, and other editor metadata.[Android IME guide][s21]

### Proposed for BuddyGrammar

- Preserve the existing local unigram/bigram/trigram model, but add confidence, recency, explicit deletion, and language namespaces.
- Learn user words only after repeated or explicit acceptance; one accidental misspelling must not become a high-priority word.
- Maintain casing variants and phrase templates separately from raw word frequency.
- Detect code-switching at the word/character level and blend enabled language models instead of forcing a global manual switch.
- Use subwords for Italian inflections and for other morphologically rich languages rather than requiring every surface form in a fixed lexicon.
- Condition punctuation, `.com`, `@`, return-key behavior, prediction aggressiveness, and learning policy on field type. Disable language correction in passwords and be conservative in URLs, email addresses, numbers, and code-like fields.
- Consider app/domain only as a coarse on-device feature with user control. Do not create a browsable log of what was typed in each app.

## 7. Gesture typing

### Evidence

Gesture typing is not merely “keys crossed by a line.” Human paths reflect motor control, speed–accuracy tradeoffs, and characteristic corner shapes. A Google study modeled gesture production using minimum-jerk trajectories plus statistical via-points and showed agreement with user-produced paths.[Quinn and Zhai: Gesture-Typing Movements][s22]

Google’s production architecture scores continuous gesture paths with a spatial model, combines them with lexicon and grammar constraints, and decodes them alongside tap input.[Google Research: Machine Intelligence Behind Gboard][s2] Separate research on an invisible gesture keyboard improved performance by adapting the keyboard location from current and historical gestures, showing that gesture geometry can also personalize.[Zhu et al.][s23]

### Proposed for BuddyGrammar

The current shape/location/frequency blend is a credible prototype. Next experiments should add:

- timestamp and velocity-aware path resampling;
- user-specific start/end and corner offsets;
- context rescoring from the same language decoder used for taps;
- a learned “accept/reject” confidence threshold, not only a fixed score cutoff;
- post-gesture runner-up replacement and one-action undo;
- personal vocabulary paths after repeated acceptance;
- separate adaptation from tap typing, because glide errors depend on previous/next keys and path dynamics, not independent per-key Gaussians.

Avoid training the gesture model on its own top result. A chosen runner-up, retyped word, or ground-truth practice gesture provides a much safer label.

## 8. Confidence, undo, and trust

### Evidence

Google reports using reverted autocorrections as negative signals and suggestion picks as positive signals when training its spatial system.[Google Research: Machine Intelligence Behind Gboard][s2] Apple’s underlined correction and tap-to-revert design makes an automatic change visible and recoverable.[Apple WWDC23 keynote][s14] The anchored-target study warns that even rare cases where a key becomes impossible can be intensely frustrating.[Gunawardana, Paek, and Meek][s1]

### Proposed for BuddyGrammar

Every automatic intervention should record:

```text
literal input, replacement, score margin, feature version,
whether it was reverted, time-to-revert, and final committed span
```

Store aggregate learning signals rather than a readable sentence history wherever possible.

Trust rules:

- never silently modify a central anchored tap;
- briefly mark every automatic word change;
- one tap or immediate backspace restores the literal form;
- after a revert, suppress that mapping in the same context and reduce its learned weight;
- let the user inspect/delete learned words and reset personalization;
- provide “suggestions only” and “literal mode” controls;
- do not auto-correct when confidence calibration is unavailable for that language/mode.

## 9. Accessibility and situational impairment

### Evidence

Apple recommends 44×44 pt as the default iOS/iPadOS control size and emphasizes adequate spacing for people with limited dexterity or mobility.[Apple Accessibility HIG][s24] Android recommends at least 48×48 dp touch targets and notes that Compose can expand a small visual element’s touch target, while warning about overlapping expanded targets.[Android Accessibility guidance][s25]

For users with motor impairments, a single average touch model is insufficient. Microsoft’s Smart Touch mapped arbitrary contact shapes to intended points and placed predicted coordinates more than three times closer to intended targets than the compared native techniques in its study.[Mott et al.: Smart Touch][s26] Cluster Touch combined a population prior with a user-specific model and improved accuracy after only 20 personal examples in studies involving motor and walking-related impairments.[Mott and Wobbrock: Cluster Touch][s27]

Multimodal feedback can help people notice errors without constantly shifting gaze between keys and text. One studied combination reduced keystrokes per character by 8% and correction backspaces by 28%, though that exact interface and population should not be assumed to generalize.[Paek et al.][s28]

### Proposed for BuddyGrammar

- Preserve minimum physical target size even when invisible posterior regions change.
- Offer an accessibility profile with wider anchors, lower autocorrect aggression, larger suggestion targets, longer long-press delay, adjustable repeat rate, and optional high-contrast key previews.
- Detect and honor VoiceOver/TalkBack/touch-exploration mode; do not let custom whole-surface gesture routing erase per-key accessibility semantics.
- Make haptic/audio feedback optional and respect system settings.
- Add one-handed/split layout choices before trying to infer them silently.
- Allow a short opt-in calibration session that learns tremor or systematic offset from a population prior.
- Evaluate separately for walking, one-thumb, two-thumb, assistive touch, screen reader, and motor-impaired cohorts. An aggregate WPM gain can hide an accessibility regression.

## 10. Privacy and platform limits

### Evidence

Apple custom keyboards run separately from the host editor and interact through a text-document proxy. By default they have no network access or shared container; enabling open access expands capability and responsibility. Apple explicitly frames keystroke safety, minimized use of other user data, and accuracy as trust requirements. Secure and phone-number fields use the system keyboard rather than a custom keyboard.[Apple Custom Keyboard Guide][s29]

Android tells IMEs to inspect `EditorInfo.inputType`, reset state between fields, hide passwords in both keyboard and candidate UI, and never store passwords.[Android IME guide][s21]

### Proposed for BuddyGrammar

- Keep tap-offset aggregates, personal vocabulary, and practice mastery on device by default.
- Never learn from secure fields; also disable learning for incognito/no-personalized-learning flags and conservative field classes.
- Store spatial statistics in unordered aggregates/buckets rather than raw timestamped trajectories after the short label window closes.
- Make cloud rewriting a separate explicit action from keyboard intelligence. Tap decoding, autocorrection, prediction, and practice selection should not require network access.
- Provide clear controls to view/reset learned vocabulary, spatial calibration, and practice history independently.
- If population learning is later needed, use federated aggregation with formal privacy protection; “data stays on device during training” alone is not a complete privacy guarantee.

## 11. Emerging on-device LLM direction

### Evidence

Google’s 2025 production research reports that small language models continue to power core completion, prediction, slide-to-type, and suggestion, while larger models handle opt-in proofreading. Synthetic mobile-style data improved next-word pretraining, and private federated fine-tuning remained important.[Google: Synthetic and Federated Mobile LMs][s30]

The 2026 HuoziIME demonstration explores a lightweight on-device LLM with hierarchical personal memory and synthesized personalization data.[Shan, Xu, and Che][s31] It is useful evidence that generative IME personalization is technically active in 2026, but it is an early system demonstration, not evidence that an LLM should replace the latency-critical tap decoder.

### Proposed for BuddyGrammar

Use an LLM only as a later, separate layer:

- generate or validate practice prompts offline/on device;
- propose multiword completions when the user explicitly invokes them;
- rewrite/proofread after text is committed;
- create synthetic typo pairs for testing, without using private user text.

Do not put an LLM in the critical per-tap path. The core decoder needs predictable latency, deterministic literal fallbacks, small memory use, calibrated confidence, and exact tests. A hybrid candidate/rescoring layer is safer than replacement.

## 12. Recommended experimental sequence

### Experiment 0 — Instrumentation only

Capture normalized touch point, visible key, expected key in practice, orientation, input mode, and correction outcome. Persist only aggregates after alignment. Establish baselines for WPM, uncorrected error, backspaces, WMR-like post-commit edits, suggestion acceptance, correction reverts, and p50/p95 input latency.

**Gate:** telemetry is excluded from secure/sensitive fields, resettable, and has no measurable typing-latency impact.

### Experiment 1 — Adaptive practice sampler

Replace the static Keyboard Lab sentence with curated prompts selected from a mastery vector. Compare static-random practice with weakness+spacing+coverage practice. Test transfer on an untouched holdout set.

**Gate:** holdout error or hesitation improves without reducing completion rate or practice satisfaction.

### Experiment 2 — Shadow spatial decoder

Run the probabilistic decoder without changing output. Log when it disagrees with the literal hit and whether the user later deletes/retypes. Use practice prompts for clean accuracy measurement.

**Gate:** a stable region of score margins shows better intended-key accuracy than static geometric hit testing.

### Experiment 3 — Anchored contextual targets

Enable posterior hit regions only outside guaranteed central anchors. Keep visible layout fixed. Start with a generic spatial model and a bounded character prior; then compare personal offsets.

**Gate:** fewer neighbor substitutions and backspaces, no loss in central literal-key reliability, no increase in correction reverts, and no OOV/name trap.

### Experiment 4 — Word lattice and confidence policy

Retain alternatives through the word boundary and add literal/correction candidates, bounded edit paths, and context rescoring. Calibrate suggestion versus autocorrect thresholds.

**Gate:** reduced post-commit word modifications and backspaces; auto-correction revert rate must not worsen.

### Experiment 5 — Personalized next-word and multilingual models

Add recency, explicit negative signals, OOV admission rules, and lightweight language detection to the existing personal model. Test suggestion gating as well as accuracy.

**Gate:** higher accepted keystroke savings without increased attention time or unwanted corrections.

### Experiment 6 — Gesture and touch-feature personalization

Add timing, velocity, contact geometry, and user-specific gesture parameters after tap decoding is stable.

**Gate:** lower wrong-gesture commits and runner-up replacements, stratified by device and language.

## 13. Evaluation checklist

Measure the entire correction cost, not just top-1 prediction accuracy:

- characters/words modified after initial commit;
- uncorrected and corrected error rate;
- backspaces and cursor-edit operations per character;
- bad-autocorrect rate and time to revert;
- literal OOV survival rate;
- WPM and keystrokes saved;
- suggestion glance/selection cost where measurable;
- decoder latency and memory on low-, mid-, and high-end devices;
- practice holdout transfer and retention after a delay;
- cold-start versus personalized cohorts;
- language, device, orientation, posture, and accessibility cohorts;
- privacy invariants and secure-field exclusions.

Use replay tests built from consented or synthetic touch traces, deterministic unit tests for anchors and literal fallbacks, and live randomized experiments for behavior. Offline accuracy alone cannot measure attention, trust, or whether users notice a wrong correction.

## 14. Highest-value conclusions

1. **Implement probability regions, not moving keys.** Context should shift ambiguous borders invisibly while a central anchor preserves literal control.
2. **Use practice as supervised calibration.** It is the cleanest source of intended-key labels and can personalize both the curriculum and touch model.
3. **Learn spatial and language behavior separately.** Personal key offsets and personal vocabulary solve different errors and should be independently resettable.
4. **Keep alternatives until the word boundary.** Whole-word decoding is much stronger than a greedy per-tap choice.
5. **Confidence and undo are model features.** A correction system without calibrated abstention and instant revert will lose trust even if aggregate accuracy rises.
6. **Start with means, not a neural net.** Production evidence supports personalized key-center offsets; full covariance did not add measurable benefit in Gboard’s study.
7. **Gate suggestions by expected value.** More suggestions can reduce keystrokes while still slowing users through attention cost.
8. **Treat privacy and accessibility as architecture.** Aggregate on device, exclude sensitive fields, preserve semantic keys, and test cohorts separately.
9. **Keep LLMs out of the tap loop.** Use them later for practice generation, proofreading, or candidate rescoring behind a deterministic decoder.

## Primary sources

[s1]: https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/paper-final.pdf "Gunawardana, Paek, and Meek — Usability Guided Key-Target Resizing for Soft Keyboards (IUI 2010)"
[s2]: https://research.google/blog/the-machine-intelligence-behind-gboard/ "Google Research — The Machine Intelligence Behind Gboard"
[s3]: https://arxiv.org/abs/2209.11311 "Sivek and Riley — Spatial Model Personalization in Gboard (2022)"
[s4]: https://developer.apple.com/documentation/uikit/uitouch "Apple Developer — UITouch"
[s5]: https://developer.android.com/reference/android/view/MotionEvent "Android Developers — MotionEvent"
[s6]: https://research.google/pubs/can-capacitive-touch-images-enhance-mobile-keyboard-decoding/ "Lertvittayakumjorn et al. — Can Capacitive Touch Images Enhance Mobile Keyboard Decoding? (UIST 2024)"
[s7]: https://www.yorku.ca/mack/chapter4.html "I. Scott MacKenzie — Evaluation of Text Entry Techniques"
[s8]: https://aclanthology.org/P16-1174/ "Settles and Meeder — A Trainable Spaced Repetition Model for Language Learning (ACL 2016)"
[s9]: https://arxiv.org/abs/1704.03987 "Ouyang et al. — Mobile Keyboard Input Decoding with Finite-State Transducers (2017)"
[s10]: https://research.google/pubs/effects-of-language-modeling-and-its-personalization-on-touchscreen-typing-performance/ "Fowler et al. — Effects of Language Modeling and its Personalization on Touchscreen Typing Performance (CHI 2015)"
[s11]: https://aclanthology.org/2024.emnlp-industry.93/ "Neural Search Space in Gboard Decoder (EMNLP Industry 2024)"
[s12]: https://rc.signalprocessingsociety.org/conferences/icassp-2023/spsicassp23vid0816 "Bellegarda — Prefix-Level Detection and Autocorrection of Keyboard Input Errors (ICASSP 2023)"
[s13]: https://research.google/pubs/a-costbenefit-study-of-text-entry-suggestion-interaction/ "Quinn and Zhai — A Cost–Benefit Study of Text Entry Suggestion Interaction (CHI 2016)"
[s14]: https://developer.apple.com/videos/play/wwdc2023/111/?time=3894 "Apple WWDC23 keynote — keyboard intelligence, inline prediction, and correction revert"
[s15]: https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/fa1e65cb3a5dcce6299a6dd067cee95720107307/java/src/com/android/inputmethod/latin/personalization/UserHistoryDictionary.java "AOSP LatinIME — UserHistoryDictionary source"
[s16]: https://arxiv.org/abs/1811.03604 "Hard et al. — Federated Learning for Mobile Keyboard Prediction (2018)"
[s17]: https://aclanthology.org/2023.acl-industry.60/ "Xu et al. — Federated Learning of Gboard Language Models with Differential Privacy (ACL 2023)"
[s18]: https://research.google/blog/improving-gboard-language-models-via-private-federated-analytics/ "Google Research — Improving Gboard Language Models via Private Federated Analytics (2024)"
[s19]: https://arxiv.org/abs/2201.06469 "Kabel et al. — Handling Compounding in Mobile Keyboard Input (2022)"
[s20]: https://developer.apple.com/documentation/uikit/uitextdocumentproxy "Apple Developer — UITextDocumentProxy"
[s21]: https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method "Android Developers — Create an Input Method"
[s22]: https://research.google/pubs/modeling-gesture-typing-movements/ "Quinn and Zhai — Modeling Gesture-Typing Movements (2018)"
[s23]: https://research.google/pubs/isfree-eyes-free-gesture-typing-via-a-touch-enabled-remote-control/ "Zhu, Zheng, Zhai, and Bi — i’sFree (CHI 2019)"
[s24]: https://developer.apple.com/design/human-interface-guidelines/accessibility "Apple Human Interface Guidelines — Accessibility"
[s25]: https://developer.android.com/develop/ui/compose/accessibility/api-defaults "Android Developers — Accessibility API defaults and minimum touch targets"
[s26]: https://www.microsoft.com/en-us/research/publication/smart-touch-improving-touch-accuracy-for-people-with-motor-impairments-with-template-matching/ "Mott et al. — Smart Touch (CHI 2016)"
[s27]: https://www.microsoft.com/en-us/research/publication/cluster-touch-improving-touch-accuracy-on-smartphones-for-people-with-motor-and-situational-impairments/ "Mott and Wobbrock — Cluster Touch (CHI 2019)"
[s28]: https://www.microsoft.com/en-us/research/publication/practical-examination-multimodal-feedback-guidance-signals-mobile-touchscreen-keyboards/ "Paek et al. — Multimodal Feedback and Guidance Signals for Mobile Touchscreen Keyboards (MobileHCI 2010)"
[s29]: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html "Apple App Extension Programming Guide — Custom Keyboard"
[s30]: https://research.google/blog/synthetic-and-federated-privacy-preserving-domain-adaptation-with-llms-for-mobile-applications/ "Google Research — Synthetic and Federated Domain Adaptation for Mobile Applications (2025)"
[s31]: https://aclanthology.org/2026.acl-demo.32/ "Shan, Xu, and Che — HuoziIME: An On-Device LLM-Enhanced Input Method for Deep Personalization (ACL 2026)"
[s32]: https://act-r.psy.cmu.edu/?post_type=publications&p=14344 "Corbett and Anderson — Knowledge Tracing: Modeling the Acquisition of Procedural Knowledge (1994)"
[s33]: https://digitalcommons.memphis.edu/facpubs/8350/ "Pavlik, Cen, and Koedinger — Performance Factors Analysis (2009)"
[s34]: https://pact.cs.cmu.edu/koedinger/pubs/Cen%2C%20Koedinger%20%26%20Junker06.pdf "Cen, Koedinger, and Junker — Learning Factors Analysis (2006)"
[s35]: https://pubmed.ncbi.nlm.nih.gov/16507066/ "Roediger and Karpicke — Test-Enhanced Learning (2006)"
[s36]: https://pubmed.ncbi.nlm.nih.gov/19076480/ "Cepeda et al. — Spacing Effects in Learning (2008)"
[s37]: https://pubmed.ncbi.nlm.nih.gov/18578849/ "Rohrer and Taylor — The Shuffling of Mathematics Problems Improves Learning (2007)"
[s38]: https://aclanthology.org/2023.acl-long.567/ "Kurdi et al. — Adaptive Exercise Generation (ACL 2023)"
[s39]: https://aclanthology.org/P17-1074/ "Bryant et al. — Automatic Annotation and Evaluation of Error Types for Grammatical Error Correction (ACL 2017)"
[s40]: https://aclanthology.org/2020.latechclfl-1.10/ "Bryant and Ng — How Far Are We from Fully Automatic High Quality Grammatical Error Correction? (2020)"
[s41]: https://doi.org/10.1016/j.econedurev.2017.04.003 "Pane et al. — Informing Progress: Insights on Personalized Learning Implementation and Effects (2017)"
[s42]: https://www.microsoft.com/en-us/research/publication/a-contextual-bandit-approach-to-personalized-news-article-recommendation-3/ "Li et al. — A Contextual-Bandit Approach to Personalized Recommendation (2010)"
[s43]: https://proceedings.mlr.press/v70/wang17a.html "Wang et al. — Optimal and Adaptive Off-policy Evaluation in Contextual Bandits (2017)"
