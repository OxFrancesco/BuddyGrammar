# Mobile keyboard benchmark: what BuddyGrammar should learn

_Research date: 2026-07-20_

## Executive conclusion

The strongest mobile keyboards do not win by putting the most features above the keys. They win by making the basic typing loop feel immediate, reversible, and trustworthy, then revealing advanced help only when it has a clear benefit.

Across Apple Keyboard, Gboard, SwiftKey, Grammarly, Fleksy, Typewise, and Samsung Keyboard, the durable baseline is remarkably consistent:

- instant local key feedback;
- a layout that adapts to the active field;
- spacebar cursor control, efficient deletion, long-press accents, and predictable shift/punctuation behavior;
- conservative autocorrection with an immediate way to undo it;
- a small, stable suggestion area rather than a constantly moving control surface;
- multilingual typing that minimizes manual mode changes;
- haptics, sound, key previews, size/layout options, and accessibility that respect system preferences;
- clear treatment of sensitive fields, learned words, networking, and permissions.

The meaningful differentiators sit above that baseline: excellent voice input, handwriting, high-quality cross-language detection, writing-quality assistance, private/on-device intelligence, personalized touch models, and specialized layouts. These features work when they are additive and reversible. They create friction when they take over the core typing loop, require unexplained permissions, or turn the suggestion strip into a dense toolbar.

For BuddyGrammar, the highest-leverage product direction is therefore:

1. make every tap, correction, and edit feel local and deterministic;
2. make every machine-made change visible and reversible;
3. explain exactly when text stays on device and when a cloud feature needs access;
4. reserve generative or grammar assistance for explicit, reviewable actions;
5. use platform-native strengths instead of pretending iOS and Android keyboard capabilities are equivalent.

## Scope and evidence quality

This report prioritizes platform-owner documentation, first-party product help/privacy pages, and published HCI research. Vendor accuracy and speed claims are treated as product positioning, not independent evidence. Fleksy's current first-party material is primarily its keyboard SDK documentation, so it is useful for interaction patterns but not proof that every feature remains in a current consumer keyboard.

The benchmark separates three things that are easy to conflate:

- **Baseline expectation:** behavior users have learned across mainstream keyboards.
- **Product differentiator:** a choice that can make one keyboard meaningfully better for a segment.
- **Platform constraint:** something a third-party keyboard cannot implement, or must implement differently, because of iOS or Android architecture.

## Platform reality: iOS and Android are not symmetric

### Capability map

| Area | iOS custom keyboard extension | Android input method editor | Consequence for BuddyGrammar |
| --- | --- | --- | --- |
| Text access | Apple exposes a `UITextDocumentProxy` for insertion, deletion, cursor movement, and limited text context. A keyboard cannot control selection or use the host app's editing menu. | `InputConnection` exposes selected/surrounding text, composing spans, corrections, cursor updates, and richer editor operations. | Share correction logic, but use different editing adapters and gracefully degrade selection-aware operations on iOS. |
| Per-field layout | The extension receives keyboard traits such as email, URL, and phone-oriented types, but secure fields and some phone fields replace it with the system keyboard. | `EditorInfo.inputType` describes text, password, phone, completion, and other editor traits; the IME remains an input service. | Contextual layouts are baseline. Sensitive-field behavior must be designed separately per platform. |
| Audio/voice | Keyboard extensions have no microphone access. This is a hard platform limitation, not a missing permission dialog. | An IME can request microphone permission and provide voice input. Background/continued capture is constrained by microphone foreground-service and while-in-use rules. | Do not promise an iOS keyboard microphone. Use system Dictation or transition into the containing app. Android can support an integrated, visibly active mic. |
| Networking and shared storage | A keyboard starts in a restricted sandbox. Network access and writable shared-container access require the user to enable **Full Access**. | Network access is an ordinary app capability; Android does not present an iOS-style Full Access keyboard toggle. Enabling an IME does produce a broad system trust warning. | An iOS keyboard should remain genuinely useful without Full Access. Both platforms still need an in-product explanation of what is sent and why. |
| Sensitive fields | Secure text fields always use the system keyboard. Host apps can reject custom keyboards altogether. | Apps can mark password variants and can request `IME_FLAG_NO_PERSONALIZED_LEARNING`, although Android explicitly says the latter is a request, not an enforceable guarantee. | Never infer that one cross-platform privacy rule is sufficient. Avoid learning in password/payment-like contexts even when the host hint is absent or malformed. |
| Keyboard UI | A custom keyboard is confined to its extension view. It cannot place correction UI by the app's insertion point or draw key artwork outside the keyboard's bounds. | An IME owns input and candidate views and can participate in inline autofill; Android also supports system stylus-handwriting integration. | Keep iOS help inside a stable keyboard surface. Android may support richer candidates and handwriting, but visual density still needs discipline. |
| Performance boundary | The keyboard is a separate extension communicating with the host through a proxy. | The IME is a service and many `InputConnection` reads cross an IPC boundary. Android warns that surrounding/selected-text reads can be expensive or time out. | Keep tap handling, layout, and first-pass correction local. Do not put host-text round trips or network work on the keypress path. |

Sources: [Apple: handling text interactions](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards), [Apple: configuring the interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface), [Apple custom keyboard programming guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html), [Apple: configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard), [Android: create an IME](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method), [`InputMethodService`](https://developer.android.com/reference/android/inputmethodservice/InputMethodService), [`InputConnection`](https://developer.android.com/reference/android/view/inputmethod/InputConnection), [`IME_FLAG_NO_PERSONALIZED_LEARNING`](https://developer.android.com/reference/android/view/inputmethod/EditorInfo#IME_FLAG_NO_PERSONALIZED_LEARNING), [Android microphone foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types#microphone).

### Product choices should not be mislabeled as platform limits

Several competitor differences are choices, not unavoidable OS restrictions:

- Grammarly uses a custom keyboard on iOS, but on Android it now offers a floating writing-assistance widget that works above the user's chosen keyboard. Android permits both patterns; Grammarly chose to preserve the user's keyboard while asking for overlay/accessibility capabilities. ([Grammarly Android guide](https://support.grammarly.com/hc/en-us/articles/15606282682637-Grammarly-for-Android-user-guide), [Android privacy explanation](https://support.grammarly.com/hc/en-us/articles/115003350672-How-Grammarly-protects-your-privacy-on-Android))
- SwiftKey's translator is available on Android but not iOS. Full Access can technically permit networking on iOS, so this is a product/implementation difference rather than proof that translation is impossible there. ([SwiftKey Translator](https://support.microsoft.com/en-us/swiftkey-keyboard/how-to-use-microsoft-translator-with-your-microsoft-swiftkey-keyboard), [SwiftKey Full Access](https://support.microsoft.com/en-us/swiftkey-keyboard/why-does-my-microsoft-swiftkey-keyboard-need-full-access-in-ios))
- SwiftKey does not expose its Android resize control on iOS. Apple constrains the extension surface, but third-party keyboards still make their own height and layout decisions inside it; the exact parity gap is a product choice within narrower platform bounds. ([SwiftKey resize](https://support.microsoft.com/en-US/swiftkey-keyboard/how-to-resize-microsoft-swiftkey-keyboard))
- Gboard's advanced voice features and handwriting are heavily device, OS, and language gated. Android enables these modalities, while Google chooses the supported device/language matrix. ([Gboard advanced voice typing](https://support.google.com/gboard/answer/11197787?hl=en), [Gboard handwriting](https://support.google.com/gboard/answer/9108773))

## Baseline keyboard expectations

These are no longer compelling headline features. Their absence, inconsistency, or sluggishness makes a keyboard feel unfinished.

### 1. Immediate, deterministic typing

A key press should update the key state and text without waiting for prediction, grammar, context retrieval, or a network call. Android's own API documentation warns that text reads through `InputConnection` may incur costly cross-process round trips and may fail if the editor is slow. SwiftKey separately documents that process reloads, multiple active languages, and Flow can increase perceived startup or typing lag. These are strong signals to isolate the hot path and budget expensive work explicitly. ([Android `InputConnection`](https://developer.android.com/reference/android/view/inputmethod/InputConnection), [SwiftKey performance troubleshooting](https://support.microsoft.com/en-us/swiftkey-keyboard/troubleshooting-for-performance-issues-in-microsoft-swiftkey-keyboard))

Expected tactile/visual feedback includes key previews, haptics or sound that respect settings, and no visible relayout on each character. Apple exposes keyboard haptics/sound as user controls; Android explicitly lists a virtual keyboard press as an appropriate semantic haptic use and recommends `performHapticFeedback`, which respects system settings without a vibration permission. Samsung exposes character previews, sounds, and vibration, while Gboard exposes haptic strength as well as a toggle. ([Apple typing guide](https://support.apple.com/en-au/guide/iphone/iph3c50f96e/ios), [Android haptic feedback](https://developer.android.com/develop/ui/views/haptics/haptic-feedback), [Samsung keyboard basics](https://www.samsung.com/uk/support/mobile-devices/how-do-i-use-the-keyboard-on-my-phone/), [Gboard preferences](https://support.google.com/gboard/answer/6102154?hl=en))

BuddyGrammar implication: prediction may trail typing by a frame or more; typing must never trail prediction. Measure cold-show latency, warm-show latency, key-down-to-visual feedback, key-down-to-committed-text, candidate refresh time, and dropped/duplicated input at p50/p95/p99.

### 2. Layout adaptation by field and form factor

Email, URL, phone, numeric, search, and secure fields should present the right keys and return action. Both Apple and Android explicitly provide field metadata for this purpose. Apple also asks keyboard extensions to adapt to docked, floating, and compact widths; Samsung and SwiftKey expose one-handed, floating, split/thumb, size, or transparency modes at the product layer. ([Apple keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface), [Android IME lifecycle and input types](https://developer.android.com/reference/android/inputmethodservice/InputMethodService), [Samsung Keyboard](https://www.samsung.com/us/support/answer/ANS10002366/), [SwiftKey usage guide](https://support.microsoft.com/en-US/swiftkey-keyboard/how-to-use-the-microsoft-swiftkey-keyboard))

BuddyGrammar implication: field adaptation belongs in the keyboard state machine, not as scattered special cases. A secure field should also switch the learning/telemetry policy before any surrounding text is processed.

### 3. Editing gestures users already expect

The most transferable interaction set is:

- **Hold or scrub the spacebar to move the cursor.** Apple Keyboard, Gboard, and SwiftKey teach this directly. SwiftKey also exposes the real conflict: if the spacebar swipe is used to switch layouts, cursor control needs an explicit mode choice. ([Apple typing guide](https://support.apple.com/en-au/guide/iphone/iph3c50f96e/ios), [Gboard usage](https://support.google.com/gboard/answer/2842292?co=GENIE.Platform%3DiOS&hl=en), [SwiftKey cursor control](https://support.microsoft.com/en-us/swiftkey-keyboard/how-do-i-use-cursor-control-on-my-microsoft-swiftkey-keyboard))
- **Efficient deletion beyond single characters.** SwiftKey supports a right-to-left word-delete gesture when Flow is off; Fleksy's SDK supports swipe-left word deletion and drag-hold deletion; Grammarly exposes distance-sensitive swipe deletion; Typewise lets a user continue deleting with a hold-and-swipe and swipe back to restore over-deleted text. ([SwiftKey usage guide](https://support.microsoft.com/en-US/swiftkey-keyboard/how-to-use-the-microsoft-swiftkey-keyboard), [Fleksy Android configuration](https://docs.fleksy.com/sdk-android/api-reference-android/keyboardconfiguration/), [Grammarly iOS settings](https://support.grammarly.com/hc/en-us/articles/360041391992-Managing-your-keyboard-settings-in-Grammarly-for-iPhone), [Typewise support](https://www.typewise.app/support))
- **Long-press accents and alternate symbols.** Apple, Gboard, Grammarly, and SwiftKey all expose accent/alternate-character behavior. ([Apple typing guide](https://support.apple.com/en-au/guide/iphone/iph3c50f96e/ios), [Gboard usage](https://support.google.com/gboard/answer/2842292?co=GENIE.Platform%3DiOS&hl=en), [Grammarly settings](https://support.grammarly.com/hc/en-us/articles/360041391992-Managing-your-keyboard-settings-in-Grammarly-for-iPhone), [SwiftKey setup](https://support.microsoft.com/en-us/swiftkey-keyboard/how-to-set-up-microsoft-swiftkey-keyboard))
- **Common text accelerators.** Double-space punctuation, auto-capitalization, caps lock, one-handed reachability, and native text replacements appear across stock and third-party products.

Gesture collisions are a product-design problem. Fleksy's SDK notes conflicts between swipe typing and swipe-left deletion; SwiftKey disables its word-delete gesture when Flow owns the gesture; cursor-on-space may collide with spacebar language switching. BuddyGrammar should give every important action one dependable default, expose conflicts honestly, and avoid gesture-only functionality with no visible or accessible alternative.

### 4. Autocorrection must be transparent and reversible

The shared best practice is not simply “have autocorrect.” It is a complete trust loop:

1. show that a correction occurred;
2. let Backspace immediately restore the original;
3. let the user reject or remove a bad candidate;
4. learn from repeated rejection without making the user visit settings;
5. expose a personal dictionary and a way to clear learned data;
6. allow autocorrection and candidate types to be disabled.

Apple temporarily underlines corrections and lets Delete restore the original; continuing to reject a suggestion causes the keyboard to stop offering it. Gboard and Grammarly document Backspace-to-undo, and Gboard lets users remove a candidate from future suggestions. SwiftKey and Samsung let a user long-press an unwanted prediction to remove it. Fleksy's SDK makes “undo correction on backspace” an explicit configuration. Typewise's Smart Bar offers one-tap correction undo and uses that feedback to personalize. ([Apple predictive text](https://support.apple.com/guide/iphone/use-predictive-text-iphd4ea90231/26/ios/26), [Gboard suggestions](https://support.google.com/gboard/answer/7068415), [Grammarly settings](https://support.grammarly.com/hc/en-us/articles/360041391992-Managing-your-keyboard-settings-in-Grammarly-for-iPhone), [SwiftKey usage guide](https://support.microsoft.com/en-US/swiftkey-keyboard/how-to-use-the-microsoft-swiftkey-keyboard), [Samsung predictive text](https://www.samsung.com/uk/support/mobile-devices/how-can-i-personalise-and-turn-predictive-text-on-and-off-on-my-samsung-galaxy-device/), [Fleksy iOS configuration](https://docs.fleksy.com/sdk-ios/api-reference-ios/keyboardconfiguration/), [Typewise support](https://www.typewise.app/support))

A controlled study of mobile text-entry aids found that a wrong autocorrection took an average of about 5.5 seconds to repair. Separately, a “restorable backspace” study found that making accidental deletion reversible reduced correction effort and improved performance. The design lesson is broader than either technique: reversibility is part of performance, not merely an error-recovery convenience. ([Alharbi et al., frustration with text-entry aids](https://vvise.iat.sfu.ca/pubs/alharbi2020frustration), [Arif et al., smart/restorable backspace](https://vvise.iat.sfu.ca/pubs/arif2016smartbackspace))

BuddyGrammar implication: never let grammar rewriting masquerade as ordinary autocorrection. Limit automatic changes to high-confidence local corrections at the just-completed token boundary. Treat phrase rewrites, tone changes, and grammar transformations as explicit proposals with a preview and a single-step revert.

### 5. Suggestions should earn their visual and cognitive cost

Suggestion strips are conventional, but more candidates are not automatically better. The largest published mobile typing study in this source set, covering 37,370 participants, found autocorrection positively associated with entry rate while word prediction was negatively associated; it is observational and self-selected, so it should guide hypotheses rather than prove causation. A controlled 170-person study found word prediction saved characters but added roughly two seconds per phrase. A 2025 eye-tracking study found that users frequently looked at candidates without selecting them and sometimes typed a word manually even after looking at the correct suggestion. ([Typing37K paper](https://userinterfaces.aalto.fi/typing37k/resources/Mobile_typing_study.pdf), [Alharbi et al.](https://vvise.iat.sfu.ca/pubs/alharbi2020frustration), [Li and Feit, suggestion gaze study](https://cix.cs.uni-saarland.de/?p=547))

This does not mean removing suggestions. A study of 15,162 people found that slower typists used suggestions more often even though the behavior could slow them, and identified multiple distinct strategies such as completion, correction, and next-word selection. Suggestions can reduce motor effort, spelling burden, or uncertainty even when they do not maximize words per minute. ([ETH Research Collection: text prediction strategies](https://www.research-collection.ethz.ch/items/6220cefa-e3cf-4f3e-be2f-190cccb089a7))

BuddyGrammar implication:

- give corrections first claim on the candidate area;
- favor high-value completions of long, rare, or uncertain words over generic next-word filler;
- keep candidate positions stable while the user is deciding;
- do not animate or repopulate the whole strip after every keystroke;
- separate candidates from tools so a button never moves under a user's finger;
- instrument candidate impressions, gaze cannot be measured directly, but “shown without use,” time-to-selection, and post-selection undo can reveal noise.

### 6. Multilingual typing should minimize mode errors

Mainstream products increasingly avoid requiring a language switch for languages that share a layout. Apple can type in two languages without manual switching and automatically swaps between the two most-used supported languages. SwiftKey supports up to five simultaneous languages on Android and automatically detects among languages sharing a layout/alphabet, while a spacebar swipe switches layouts when necessary. Gboard supports multiple enabled languages and a hold-space switcher; Google's first-party launch material also described multilingual correction and suggestions without manual switching. Grammarly's current multilingual suggestions automatically detect among 23 supported languages. Typewise positions no-switch multilingual typing as a premium capability. ([Apple language guide](https://support.apple.com/en-ca/guide/iphone/-iph73b71eb/ios), [SwiftKey usage guide](https://support.microsoft.com/en-US/swiftkey-keyboard/how-to-use-the-microsoft-swiftkey-keyboard), [Gboard languages](https://support.google.com/gboard/answer/7068494?hl=en), [Google Gboard launch](https://blog.google/products-and-platforms/products/search/gboard-now-on-android/), [Grammarly multilingual suggestions](https://support.grammarly.com/hc/en-us/articles/39345737251469-Introducing-Multilingual-Suggestions), [Typewise support](https://www.typewise.app/support))

BuddyGrammar implication: distinguish **language model selection** from **physical layout selection**. Detect compatible languages at phrase/session level with hysteresis, keep the user's chosen layout stable, and make the active languages inspectable. Rapidly changing the model after a borrowed word is worse than requiring a deliberate switch.

### 7. Privacy state must be understandable at the keyboard surface

Apple frames Full Access as an explicit trust decision because it enables networking and writable shared storage, and notes that users expect keystrokes to go only to the destination field. SwiftKey's iOS explanation says Full Access is used for networking and its shared model/settings container, while asserting that text is not transmitted unless account features are enabled. Grammarly is more direct: its cloud checks require Full Access; without it, the keyboard still types but Grammarly checking is unavailable. ([Apple open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard), [SwiftKey Full Access](https://support.microsoft.com/en-us/swiftkey-keyboard/why-does-my-microsoft-swiftkey-keyboard-need-full-access-in-ios), [Grammarly Full Access](https://support.grammarly.com/hc/en-us/articles/115000730091-Why-Grammarly-needs-full-access-on-iOS))

Gboard's privacy controls distinguish federated learning, device-stored personalization, deletion of learned data, and a separate opt-in voice-audio donation program. SwiftKey distinguishes device-only learning from optional account sync and provides a data portal. Typewise offers an explicitly offline version and says typing data remains on device. Fleksy's current SDK positioning says keyboard text remains local to the integrating client's host application, while its configuration also makes clear that a client can opt into event capture—an important reminder that SDK privacy depends on the integrating app's choices. ([Gboard privacy](https://support.google.com/gboard/answer/12373137?hl=en), [SwiftKey data sharing](https://support.microsoft.com/en-us/topic/microsoft-swiftkey-keyboard-sharing-your-typing-data-faq-d737059d-8810-448e-b376-9af56171a37d), [SwiftKey data portal](https://support.microsoft.com/en-US/swiftkey-keyboard/microsoft-swiftkey-keyboard-data-portal), [Typewise privacy](https://www.typewise.app/blog/privacy-typewise-keyboard-secure), [Fleksy privacy](https://www.fleksy.com/privacy/), [Fleksy Android configuration](https://docs.fleksy.com/sdk-android/api-reference-android/keyboardconfiguration/))

BuddyGrammar implication: “we value privacy” is insufficient. The keyboard should display clear states such as **Local**, **Cloud help available**, **Sensitive field**, **Offline**, or **Full Access required**, each opening a concise data-flow explanation. Full Access should unlock particular named features; it should not be an unexplained prerequisite for the basic keyboard.

### 8. Accessibility is a core input mode, not a compatibility checkbox

Apple provides VoiceOver typing modes and Typing Feedback that can speak characters, words, corrections, capitalization, and predictions. Android flags special considerations for inline suggestions when touch exploration is active, because a conventional autofill menu may work better for many users. SwiftKey explicitly disables Flow when Explore by Touch is enabled. Samsung offers high-contrast keyboards and size/color controls; Google's TalkBack and braille keyboard integrations expose modality-specific gestures. ([Apple VoiceOver typing](https://support.apple.com/en-euro/111796), [Apple Typing Feedback](https://support.apple.com/en-us/111779), [Android `InputMethodInfo`](https://developer.android.com/reference/android/view/inputmethod/InputMethodInfo), [SwiftKey Flow](https://support.microsoft.com/en-us/swiftkey-keyboard/what-is-flow-and-how-do-i-enable-it-with-microsoft-swiftkey-keyboard), [Samsung Keyboard](https://www.samsung.com/us/support/answer/ANS10002366/), [TalkBack braille keyboard](https://support.google.com/accessibility/android/answer/9728765?hl=en))

BuddyGrammar implication: every gesture needs an accessibility action; candidate changes should be announced without flooding speech; key labels and states need stable semantics; reduced motion and high contrast should not be afterthought themes; and the keyboard must be usable with swipe typing and other gesture modes disabled.

## Differentiators worth pursuing

### Voice that remains part of the editing flow

Apple's stock Dictation keeps the keyboard visible, supports switching between touch and voice, and can process many languages on device. Gboard's advanced voice typing on supported Pixel devices adds punctuation, emoji, editing commands, field navigation, a persistent mic mode, and selected cloud-assisted edits while explaining which text leaves the device. SwiftKey's current Android voice mode also keeps the keyboard visible so users can type and speak together. These products make voice valuable because it is an editing modality, not a modal “record, wait, receive blob” experience. ([Apple Dictation](https://support.apple.com/en-mide/guide/iphone/-iph2c0651d2/ios), [Gboard advanced voice typing](https://support.google.com/gboard/answer/11197787?hl=en), [SwiftKey voice-to-text](https://support.microsoft.com/en-US/swiftkey-keyboard/how-do-i-use-voice-to-text-with-microsoft-swiftkey-keyboard))

BuddyGrammar opportunity:

- Android: integrated mic with explicit recording state, live partials, touch-and-voice coexistence, spoken edit commands, and a hard stop when the IME is no longer visible.
- iOS: do not simulate a keyboard microphone. Provide excellent interoperability with system Dictation and, if product-worthy, a clear handoff to a containing-app dictation session followed by an explicit return to the editor.

### Handwriting where the platform makes it natural

Gboard offers a handwriting canvas on Android for supported languages, and Samsung integrates finger/S Pen handwriting plus editing gestures on supported Galaxy hardware. Android 14+ also defines system stylus-handwriting behavior for standard text fields, including select, delete, and insert gestures, while password fields are excluded. ([Gboard handwriting](https://support.google.com/gboard/answer/9108773), [Samsung Keyboard](https://www.samsung.com/us/support/answer/ANS10002366/), [Android stylus input](https://developer.android.com/develop/ui/views/touch-and-input/stylus-input/stylus-input-in-text-fields), [Android custom text editors](https://developer.android.com/develop/ui/views/touch-and-input/stylus-input/custom-text-editors))

BuddyGrammar opportunity: treat Android handwriting as a later modality built on platform APIs. It is not a good cross-platform flagship while iOS keyboard extensions cannot achieve equivalent input access.

### Writing assistance with a reviewable diff

Grammarly makes corrections and alternatives visible in its completion area, offers detail mode, and previews generative rewrites before insertion. Apple's Writing Tools underline changes, let users inspect changes, compare with the original, and revert all. Samsung's Writing Assist begins with selected text and offers translation, composition, style, and spelling/grammar actions in supported contexts. ([Grammarly iPhone keyboard](https://support.grammarly.com/hc/en-us/articles/360009187612-How-does-the-Grammarly-Keyboard-work-on-iPhones), [Grammarly mobile AI](https://support.grammarly.com/hc/en-us/articles/24086943816845-How-to-use-Grammarly-s-generative-AI-on-my-mobile-device), [Apple Writing Tools](https://support.apple.com/guide/iphone/find-the-right-words-with-writing-tools-iph6f08da1d2/26/ios/26), [Samsung Writing Assist](https://www.samsung.com/us/support/answer/ANS10004612/))

BuddyGrammar opportunity: grammar assistance is the natural differentiator, but its interaction contract should be “select or invoke, preview, accept/reject, revert.” Show the exact affected span and preserve the original until the user commits. A one-word typo and a rewritten sentence should never look like the same kind of suggestion.

### Privacy as a product mode, not only a policy

Typewise's most legible differentiation is a fully offline keyboard option. Samsung offers a “process data only on device” control for Galaxy AI, with the honest tradeoff that some online functionality becomes unavailable. Gboard distinguishes on-device advanced typing from the specific edits that send field text to Google. These are understandable product modes with visible capability tradeoffs. ([Typewise privacy](https://www.typewise.app/blog/privacy-typewise-keyboard-secure), [Samsung Galaxy AI privacy controls](https://news.samsung.com/us/knox-control-your-security-privacy-settings-data/), [Gboard advanced voice typing](https://support.google.com/gboard/answer/11197787?hl=en))

BuddyGrammar opportunity: ship a credible local-only mode. Cloud grammar/rewrite actions should be separately enabled and clearly labeled, with exact scope, retention/training choices, and a visible cancel path.

### Personalized touch and correction models

Typewise says it adapts to where a user tends to strike each key and learns from correction undo; SwiftKey and Gboard expose personalized language-model controls. The general opportunity is valid even when vendor accuracy claims are not independently verified: personalization should learn from explicit outcomes such as accepted typing, immediate undo, dictionary additions, and repeat corrections, while remaining resettable and ideally local. ([Typewise AI internals](https://www.typewise.app/blog/inside-the-ai-how-we-build-our-autocorrect-emoji-and-text-prediction-engine), [SwiftKey personalization](https://support.microsoft.com/en-US/swiftkey-keyboard/how-do-i-personalize-my-typing-with-microsoft-swiftkey-keyboard), [Gboard privacy and learning](https://support.google.com/gboard/answer/12373137?hl=en))

BuddyGrammar opportunity: begin with transparent feedback signals before attempting opaque “learn everything” personalization. Let users inspect/remove learned words and reset touch or language personalization independently.

### Alternate layouts for a willing niche

Typewise's hexagonal layout and Fleksy's gesture-first design show that keyboards can differentiate structurally. Typewise also publicly acknowledged that many people abandoned the product because the hex layout and gestures imposed a learning curve, and that better onboarding was necessary. Its current product therefore offers both hexagonal and traditional layouts. ([Typewise support](https://www.typewise.app/support), [Typewise onboarding retrospective](https://www.typewise.app/blog/typewise-keyboard-2022), [Fleksy Android configuration](https://docs.fleksy.com/sdk-android/api-reference-android/keyboardconfiguration/))

BuddyGrammar opportunity: keep familiar QWERTY/QWERTZ/AZERTY as the default. Experimental ergonomic layouts can become an opt-in lab with a short interactive tutorial, visible gesture hints, progress metrics, and a one-tap return to the familiar layout. Do not make novelty the admission price for grammar assistance.

## Competitor lessons at a glance

| Product | Baseline strengths | Real differentiator | Recurring friction or tradeoff | Lesson for BuddyGrammar |
| --- | --- | --- | --- | --- |
| Apple Keyboard | polished cursor trackpad, accents, one-handed layout, transparent autocorrect undo, mixed tap/QuickPath, strong system integration | on-device-capable Dictation, inline predictions, Writing Tools | many capabilities are unavailable to third-party extensions; some language/device/region gating | Match the learned editing baseline and be explicit about extension limits. |
| Gboard | glide typing, candidate removal, cursor scrub, rich language/theme/haptic settings | Pixel advanced voice, Android handwriting, federated/on-device learning controls | complex device/language gating; some edits send field text to Google; language-switch controls can conflict | Gate features honestly and expose data flow per action. |
| SwiftKey | Flow/tap coexistence, word-delete gesture, layouts/modes, customizable toolbar, mature multilingual typing | deep personalization, account sync, inline translation on Android | Flow conflicts with delete/accessibility; multiple languages can affect performance; toolbar can become dense | Design gesture precedence, performance budgets, and a compact default toolbar. |
| Grammarly | familiar keyboard settings, Backspace undo, explicit correction cards | high-quality grammar/style/rewrite assistance; Android overlay preserves chosen keyboard | cloud dependence, iOS Full Access, Android overlay/accessibility permissions, some app blocking | Grammar help should be explicit and reviewable; explain permissions in feature terms. |
| Fleksy | configurable correction/undo, gesture deletion, themes | gesture-first SDK, privacy-oriented local integration, extensible top bar | gesture collisions; current public evidence is SDK-centric; integrations can opt into sensitive event capture | Gesture power needs visible fallbacks and a strict client-side data contract. |
| Typewise | traditional layout option, correction undo, text replacements, language support | hex layout, reversible scrub deletion, local/offline positioning, touch personalization | substantial learning curve and early abandonment acknowledged by the vendor | Novel input can be an optional mode, never a prerequisite. |
| Samsung Keyboard | extensive field/layout customization, prediction controls, high contrast, modes, toolbar reordering | S Pen handwriting, Galaxy AI writing tools, device-only AI control | capability varies by Galaxy device/app/language; toolbar breadth creates complexity | Personalize and reorder advanced tools, but keep typing controls visually stable. |

Primary product hubs: [Apple iPhone typing](https://support.apple.com/en-au/guide/iphone/iph3c50f96e/ios), [Gboard Help](https://support.google.com/gboard/?hl=en), [Microsoft SwiftKey Help](https://support.microsoft.com/en-us/swiftkey), [Grammarly mobile keyboard](https://support.grammarly.com/hc/en-us/articles/360009187612-How-does-the-Grammarly-Keyboard-work-on-iPhones), [Fleksy SDK documentation](https://docs.fleksy.com/), [Typewise support](https://www.typewise.app/support), [Samsung Keyboard](https://www.samsung.com/us/support/answer/ANS10002366/).

## Toolbar and suggestion-surface design

The toolbar is where otherwise good keyboards accumulate accidental complexity. SwiftKey makes its GIF, Clipboard, Translator, Stickers, and other tools customizable. Samsung allows toolbar reordering and includes emoji, GIFs, voice, handwriting, search, translation, clipboard, text editing, and AI writing features. Fleksy's SDK exposes a customizable top-bar action. Grammarly uses its limited top area for the correction/writing task rather than trying to become an app launcher. ([SwiftKey Help](https://support.microsoft.com/en-us/swiftkey), [Samsung Keyboard](https://www.samsung.com/us/support/answer/ANS10002366/), [Fleksy Android configuration](https://docs.fleksy.com/sdk-android/api-reference-android/keyboardconfiguration/), [Grammarly iPhone keyboard](https://support.grammarly.com/hc/en-us/articles/360009187612-How-does-the-Grammarly-Keyboard-work-on-iPhones))

Recommended hierarchy:

1. **Persistent typing layer:** candidates/correction status and a single entry point for tools.
2. **Contextual assistance layer:** grammar detail, rewrite, clipboard, or translation only after explicit invocation or strong contextual relevance.
3. **Customization layer:** reorder/hide tools in settings, not by making the default strip a horizontally scrolling mystery.

Keep Backspace, Return, language/switch controls, and cursor affordances independent from the changing toolbar. Never move a control into the position occupied by a candidate a moment earlier. When a cloud result is pending, preserve the user's current candidates and show a cancellable progress state in the invoked panel.

## Onboarding and permissions

Keyboard onboarding has two jobs: teach activation and establish trust. It should not be a feature tour before the keyboard works.

Recommended sequence:

1. Explain the value in one sentence and preview the familiar layout.
2. Guide system keyboard enablement/switching with platform-specific screens.
3. Let the user type in a local practice field immediately.
4. Teach only three high-value interactions in context: spacebar cursor, correction undo, and grammar preview/revert.
5. Ask for Full Access, microphone, account sync, or cloud processing only when the user invokes the feature that needs it.
6. Show what remains functional if the user declines.
7. Provide a privacy dashboard for learned words, local/cloud mode, data deletion, and permission repair.

The rationale is visible in first-party support burden. SwiftKey and Grammarly both maintain dedicated iOS Full Access explanations. Typewise says it lost users to the learning curve of its nonstandard layout/gestures. Grammarly lets Android users block the assistant in particular apps and automatically blocks some categories when performance or sensitivity makes the experience unsuitable. ([SwiftKey Full Access](https://support.microsoft.com/en-us/swiftkey-keyboard/why-does-my-microsoft-swiftkey-keyboard-need-full-access-in-ios), [Grammarly Full Access](https://support.grammarly.com/hc/en-us/articles/115000730091-Why-Grammarly-needs-full-access-on-iOS), [Typewise onboarding retrospective](https://www.typewise.app/blog/typewise-keyboard-2022), [Grammarly blocked apps](https://support.grammarly.com/hc/en-us/articles/21602062542989-How-to-block-and-manage-blocked-apps-in-Grammarly-for-Android))

## Prioritized roadmap for BuddyGrammar

### P0 — earn trust in the core keyboard

#### 1. Establish a hard local hot-path architecture

- Key feedback, text commit, shift state, deletion, punctuation, and first-pass candidate lookup must not wait for network or host-text round trips.
- Preload compact models/resources where practical and degrade to deterministic typing while heavier systems initialize.
- Cache only the minimum surrounding context needed; on Android, batch/cap expensive `InputConnection` reads.
- Add performance traces for cold/warm keyboard show, every commit/edit operation, candidate refresh, memory-pressure recovery, and abandoned cloud requests.

Success criteria: typing remains correct with networking disabled, cloud services stalled, models unavailable, and the host editor returning no context.

#### 2. Complete the baseline editing contract

- hold/scrub spacebar cursor movement;
- hold-delete acceleration plus a discoverable word-delete action;
- reversible over-delete where feasible;
- long-press accents/alternate symbols;
- key previews, haptics, sounds, and accessibility announcements;
- field-specific layouts and return actions;
- one-handed/compact adaptation before decorative themes.

On iOS, do not imply that the keyboard can programmatically extend selection like Apple's system trackpad. On Android, use richer selection/composition APIs without making them prerequisites for basic cursor movement.

#### 3. Build the autocorrection trust loop

- visually mark a just-applied correction;
- make immediate Backspace restore the exact original;
- allow “never suggest this” and personal-dictionary addition from the strip;
- learn from repeated reversion conservatively;
- expose separate toggles for automatic correction, spelling candidates, completion, and next-word prediction;
- offer clear/reset learned words without wiping unrelated preferences.

Track correction acceptance, immediate revert, delayed manual retype, candidate removal, and false-positive rate. Raw autocorrection hit rate is not enough.

#### 4. Make privacy a live product state

- Provide a useful local-only keyboard before iOS Full Access.
- Label each networked action and its text scope before first use.
- Suppress learning, logging, and network suggestions in sensitive fields.
- Show offline/unavailable states without blocking typing.
- Separate local personalization, optional sync, product analytics, model-improvement contribution, and voice/audio contribution into distinct controls.

### P1 — make grammar assistance the focused differentiator

#### 5. Redesign the suggestion strip around confidence and intent

- corrections first;
- completion only when it saves meaningful input;
- generic next-word suggestions only when confidence/value clears a high threshold;
- stable candidate positions;
- one compact tools button instead of a default wall of features;
- accessible announcements that describe only meaningful changes.

Run experiments on task completion and repair time, not just candidate taps. A candidate can earn taps while still slowing the overall task.

#### 6. Introduce explicit, diffable grammar and rewrite actions

- separate typo correction from grammar, clarity, and rewrite categories;
- highlight the exact affected span;
- show original and proposal together;
- accept/reject per change and revert the entire operation;
- keep generation cancellable and never freeze the keyboard;
- avoid sending unrelated surrounding text when a smaller span is sufficient.

#### 7. Add robust multilingual state

- allow several compatible language models on one physical layout;
- use hysteresis so quoted or borrowed words do not flip the active language;
- show detected language unobtrusively and let the user pin it;
- provide an explicit layout switch when alphabets/layouts differ;
- keep dictionaries and personalization separable per language.

### P2 — modality and personalization

#### 8. Build platform-specific voice plans

- Android: multimodal live dictation with visible recording, touch editing, punctuation/command support, and permission-in-context onboarding.
- iOS: system Dictation compatibility first; containing-app handoff only if the round trip is demonstrably smoother than using Dictation directly.

#### 9. Personalize from trustworthy signals

- learn key-hit bias locally;
- use correction revert, dictionary action, and repeat manual repair as high-quality feedback;
- allow separate reset/export of learned language data;
- never use password-like or explicitly private fields for learning.

#### 10. Explore handwriting and alternative layouts only after baseline parity

- Android handwriting can follow platform stylus APIs and explicit device/language eligibility.
- Alternate ergonomic layouts should be opt-in, tutorialized, measurable, and instantly reversible to a standard layout.

## Evaluation plan

Benchmark BuddyGrammar with tasks that expose user cost, not only model accuracy:

| Dimension | Suggested measures |
| --- | --- |
| Latency | cold/warm show p50/p95/p99; tap-to-preview; tap-to-commit; candidate-refresh; rewrite time-to-first-result; stalled-request cancellation |
| Correctness | lost/duplicated characters; composing-state failures; cursor position after edit; field-layout correctness; mixed-language accuracy |
| Autocorrect trust | corrections per 100 words; immediate revert; delayed repair; false-positive rate; time to restore original; unwanted-candidate removals |
| Suggestion value | characters saved; time saved/lost; impressions without selection; selection latency; post-selection undo; task completion time |
| Editing | cursor-placement attempts/time; word-delete errors; restored over-deletion; long-press accuracy; gesture collision rate |
| Privacy comprehension | ability to identify local vs cloud actions; permission opt-in/decline completion; accidental sensitive-field processing; successful data reset |
| Accessibility | full task completion with VoiceOver/TalkBack; external switch/keyboard path; large text/high contrast; gesture-disabled parity; announcement overload |
| Onboarding | activation completion; first successful typing; Full Access comprehension; tutorial abandonment; time to discover undo/cursor controls |

Use representative editors, not just BuddyGrammar's demo field: messaging, browser URL/search, email, notes, forms, numeric/phone, password, multiline rich text, and editors with poor or delayed input-connection behavior. Test airplane mode, revoked permissions, low-memory relaunch, language switching mid-sentence, emoji, dictation handoff, and very long documents.

## Product principles to retain

1. **Typing is the fallback that must always work.** Every advanced system may fail independently.
2. **Automatic actions require a cheaper undo than the action saved.** A correction that takes seconds to repair is a net loss.
3. **A visible suggestion is not free.** It consumes attention even when ignored.
4. **Permissions should follow intent.** Ask when the user invokes the feature and explain what still works without it.
5. **The keyboard should disclose its data state.** Local, networked, sensitive, and unavailable modes must not look identical.
6. **Platform divergence is legitimate.** An excellent Android voice experience and an excellent iOS Dictation handoff are better than false feature parity.
7. **Novelty belongs behind familiarity.** Alternative layouts and gestures can delight motivated users without burdening everyone else.
8. **Grammar intelligence should feel like collaboration, not possession of the text.** Preview, explain, accept, reject, and revert.

## Primary source index

### Platform owners

- [Apple: Handling text interactions in custom keyboards](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)
- [Apple: Configuring a custom keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface)
- [Apple: Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [Apple: Custom Keyboard programming guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
- [Apple: Type with the onscreen keyboard](https://support.apple.com/en-au/guide/iphone/iph3c50f96e/ios)
- [Apple: Predictive text](https://support.apple.com/guide/iphone/use-predictive-text-iphd4ea90231/26/ios/26)
- [Apple: Dictation](https://support.apple.com/en-mide/guide/iphone/-iph2c0651d2/ios)
- [Apple: Writing Tools](https://support.apple.com/guide/iphone/find-the-right-words-with-writing-tools-iph6f08da1d2/26/ios/26)
- [Android: Create an input method](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method)
- [Android: `InputMethodService`](https://developer.android.com/reference/android/inputmethodservice/InputMethodService)
- [Android: `InputConnection`](https://developer.android.com/reference/android/view/inputmethod/InputConnection)
- [Android: Stylus input in text fields](https://developer.android.com/develop/ui/views/touch-and-input/stylus-input/stylus-input-in-text-fields)
- [Android: Haptic feedback](https://developer.android.com/develop/ui/views/haptics/haptic-feedback)

### Keyboard products

- [Gboard Help](https://support.google.com/gboard/?hl=en)
- [Gboard advanced voice typing](https://support.google.com/gboard/answer/11197787?hl=en)
- [Gboard privacy and learning](https://support.google.com/gboard/answer/12373137?hl=en)
- [Microsoft SwiftKey Help](https://support.microsoft.com/en-us/swiftkey)
- [SwiftKey usage guide](https://support.microsoft.com/en-US/swiftkey-keyboard/how-to-use-the-microsoft-swiftkey-keyboard)
- [SwiftKey privacy and data](https://support.microsoft.com/en-us/topic/microsoft-swiftkey-keyboard-privacy-questions-and-your-data-07e13677-6b38-4ad0-bad0-d41207cab6de)
- [Grammarly for iPhone](https://support.grammarly.com/hc/en-us/articles/360009187612-How-does-the-Grammarly-Keyboard-work-on-iPhones)
- [Grammarly for Android](https://support.grammarly.com/hc/en-us/articles/15606282682637-Grammarly-for-Android-user-guide)
- [Grammarly multilingual suggestions](https://support.grammarly.com/hc/en-us/articles/39345737251469-Introducing-Multilingual-Suggestions)
- [Fleksy Android keyboard configuration](https://docs.fleksy.com/sdk-android/api-reference-android/keyboardconfiguration/)
- [Fleksy iOS keyboard configuration](https://docs.fleksy.com/sdk-ios/api-reference-ios/keyboardconfiguration/)
- [Fleksy privacy](https://www.fleksy.com/privacy/)
- [Typewise support](https://www.typewise.app/support)
- [Typewise privacy](https://www.typewise.app/blog/privacy-typewise-keyboard-secure)
- [Samsung Keyboard](https://www.samsung.com/us/support/answer/ANS10002366/)

### Research

- [Palin et al., _How do People Type on Mobile Devices?_ (Typing37K)](https://www.repository.cam.ac.uk/items/809c909b-9301-4cad-955d-998bdce7e0e0)
- [Alharbi et al., _The Effects of Predictive Features of Mobile Keyboards on Text Entry Speed and Errors_](https://vvise.iat.sfu.ca/pubs/alharbi2020frustration)
- [Arif et al., _Evaluation of a Smart-Restorable Backspace Technique to Facilitate Text Entry Error Correction_](https://vvise.iat.sfu.ca/pubs/arif2016smartbackspace)
- [Li and Feit, _How We Type with Word Suggestions: Understanding Visual Attention and Checking Behavior during Mobile Text Input_](https://cix.cs.uni-saarland.de/?p=547)
- [Lehmann et al., _Typing Behavior is About More than Speed: Users' Strategies for Choosing Word Suggestions Despite Slower Typing Rates_](https://www.research-collection.ethz.ch/items/6220cefa-e3cf-4f3e-be2f-190cccb089a7)
