# How Wispr Flow and Typeless provide voice dictation from an iOS keyboard

Research date: 2026-07-17
Scope: current Apple documentation and App Review rules; Apple Developer Forums answers from Apple staff; current first-party Wispr Flow and Typeless help, privacy, release-note, and App Store pages; the two Typeless screenshots supplied with the research request; and BuddyGrammar's current source tree.

This is a competitor-focused companion to [`apple-keyboard-workarounds.md`](apple-keyboard-workarounds.md), not a replacement for it. That report covers supported BuddyGrammar alternatives and the local no-audio App Intent experiment in more depth.

## Executive answer

Wispr Flow and Typeless do **not** have a special ability to record audio inside an iOS custom-keyboard extension. Apple still explicitly denies custom keyboards access to the microphone and speaker. Enabling **Allow Full Access** adds networking and a writable shared container; it does not add microphone access.

Both products make dictation *look* like a keyboard feature while a second process—the installed containing app—owns the microphone:

- **Wispr Flow:** first-party support material explicitly says the keyboard launches the main Flow app to start recording. On current iOS, the user may briefly see Flow and then swipe back to the original app. Flow continues the recording, transcribes in the cloud, shares the result/state with its keyboard, and the keyboard inserts the text into the active field.
- **Typeless:** first-party release notes explicitly identify **Picture in Picture** as the mode that skips the app-switching step. The user enables the mode in the containing app and tucks its PiP window off-screen. When the user later taps Speak in the keyboard, the still-running containing app activates its microphone. The narrow chevron on the right edge of both supplied screenshots is highly consistent with Typeless's documented tucked-away PiP UI. That visual identification is an inference from the screenshots; the use of PiP itself is directly documented by Typeless.

The keyboard remains important, but its role is UI, state/control signaling, limited text context, and final insertion through `UITextDocumentProxy`. The audio session belongs to the app.

This architecture is almost the same as BuddyGrammar's current PiP/App Group/Darwin-notification bridge. The important difference is not a hidden Apple API; it is that Typeless publicly ships the PiP technique, while Wispr currently accepts a visible app handoff and augments it with system entry points such as Shortcuts, Control Center, Action Button, Live Activities, and a growing list of app-specific return paths.

## Confidence labels

- **Proven:** stated by Apple or the vendor, visible in the supplied screenshots, or present in BuddyGrammar source.
- **Strong inference:** the only architecture consistent with multiple proven facts, but the vendor has not published the implementation.
- **Unknown:** not recoverable from public documentation without binary/runtime inspection or vendor disclosure.

## 1. Apple's non-negotiable process boundary

### The custom keyboard cannot own the microphone

Apple's current [Configuring Open Access for a Custom Keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) page lists “No access to microphone and speaker” among the keyboard sandbox restrictions. With Open Access, the keyboard keeps those restrictions but gains capabilities including networking, server-side keystroke processing, and a writable container shared with its containing app. Apple explicitly says the containing app and keyboard can employ that shared container.

The older but unambiguous [Custom Keyboard extension guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) states that microphone access is unavailable and therefore dictation input is not possible inside the extension. The general [App Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html) adds that ordinary iOS extensions cannot access the microphone or perform long-running background tasks.

Therefore:

- `RequestsOpenAccess = true` / Allow Full Access does not grant an audio entitlement.
- Putting `AVAudioEngine`, `AVAudioRecorder`, SpeechAnalyzer, or `SFSpeechRecognizer` in the keyboard target cannot reproduce these competitors' audio path.
- A second keyboard extension or an internal “voice keyboard” UI mode has the same sandbox. Typeless's voice and typing panes are presentation states, not different microphone entitlements.

### What the keyboard can do

Apple's [custom-keyboard text interaction guide](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards) says a custom keyboard runs in a separate process and interacts with the active field through `UITextDocumentProxy`. The proxy can insert/delete text, move the cursor, inspect selected text, and obtain limited context before and after the cursor. This is sufficient for the keyboard to receive a completed transcript from elsewhere and call `insertText(_:)`.

Apple's [Open Access documentation](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) and [App Groups documentation](https://developer.apple.com/documentation/xcode/configuring-app-groups) support using a shared group container between an extension and its containing app. The latter also notes that App Groups enable specific IPC mechanisms between same-team processes. None of this transfers microphone permission or app lifetime into the extension.

### The containing app can record in the background, if it is genuinely recording

The containing app is an ordinary app process and may request microphone permission. Apple's [`AVAudioSession.Category.record`](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record) documentation says an app can continue recording after transitioning to the background by declaring the `audio` value in `UIBackgroundModes`. Apple's [background execution guide](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes) stresses that background modes are limited and should be used only for the service they declare.

This supports a real, user-visible recording session that begins in the app and continues while another app is foreground. It does not support an indefinitely suspended “ready” process that can later be awakened by an arbitrary keyboard message. If the containing app is suspended or terminated, a shared-container write or Darwin notification does not itself create a public wake/launch mechanism.

Speech recognition is a separate layer from audio ownership. Apple's [Speech framework](https://developer.apple.com/documentation/speech/) can recognize live or prerecorded audio in an app, but neither competitor claims to use Apple Speech. Wispr says transcription always occurs in its cloud; Typeless says audio and context are processed on its cloud servers. The competitors' main apps likely stream or upload captured audio to their services rather than rely on Apple's dictation engine.

## 2. App launching and returning are the fragile part

### Public rules are stricter than the behavior of shipping competitors

[App Review Guideline 4.4.1](https://developer.apple.com/app-store/review/guidelines/) says a keyboard must provide keyboard input, remain functional without Full Access, and must not launch other apps except Settings. Apple's [`NSExtensionContext.open`](https://developer.apple.com/documentation/foundation/nsextensioncontext/open%28_%3Acompletionhandler%3A%29) documentation says each extension point decides whether URL opening is supported and names Today and iMessage extensions on iOS; it does not name custom keyboards.

Apple DTS is even more direct in [this 2025 extension-launch answer](https://developer.apple.com/forums/thread/773342): there is no supported general way for ordinary app extensions to launch their containing app. In a separate [iOS 18 responder-chain discussion](https://developer.apple.com/forums/thread/764570), Apple DTS says bypassing the extension restriction with Objective-C runtime/responder tricks is unsupported and vulnerable to compatibility breakage.

Wispr nevertheless documents a shipping keyboard-to-main-app launch. Its App Store availability proves that Apple has accepted some version of Wispr's binary; it does **not** turn its undisclosed handoff into a documented API contract or guarantee the same review result for BuddyGrammar.

### iOS does not provide a public generic return trip

The hardest part is returning to the exact app that originally hosted the keyboard. In Apple's June 2026 answer on [iOS 26.4 keyboard round trips](https://developer.apple.com/forums/thread/826851), a DTS engineer says there is no public, App-Store-safe API for either the keyboard extension or its containing app to identify the original host app. Apple also has no documented privacy-preserving keyboard → containing app → original host round trip. Apple recommends filing an enhancement request for that high-level capability.

That explains Wispr's current behavior unusually well:

- Wispr's [iOS 26.4 support article](https://docs.wisprflow.ai/articles/6269634092-adapting-to-ios-26-4) says Start Flow used to open Flow briefly and return automatically, but now many users must manually swipe back after Flow opens.
- The same page says automatic return is rolling out for certain known apps rather than generically.
- Wispr's [July 2026 release notes](https://wisprflow.ai/whats-new) say it added “native switchback” for a named list of apps.

**Strong inference:** Wispr's generic previous-host discovery depended on an iOS implementation detail that changed in 26.4. Its new known-app support likely uses maintained, app-specific deep links or URL schemes. Public materials do not disclose the actual mechanism, so neither the old nor new return implementation should be copied based on guesswork.

## 3. Wispr Flow: facts and likely architecture

### Proven by Wispr

Wispr's [current iPhone setup guide](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone) establishes all of the following:

- The containing app must be installed, opened at least once, and signed in.
- The keyboard is enabled in Settings and **Allow Full Access** is turned on.
- The keyboard requires an internet connection to transcribe.
- Activating the microphone may take the user to the Flow app; on iOS 26.4+, the user swipes back and dictation continues.
- Its troubleshooting section refers explicitly to the keyboard launching the main app to start recording, the main app being closed during dictation, and the main app's Dynamic Island microphone indicator.

Wispr's [Shortcuts guide](https://docs.wisprflow.ai/articles/1986921789-how-to-set-up-flow-shortcuts-for-iphone) adds system-owned entry points:

- Flow provides Action Button, Back Tap, Control Center, widget, Siri, and Shortcuts paths.
- It shows a Live Activity on the Lock Screen and Dynamic Island while dictating.
- When the Flow keyboard is active, a shortcut-triggered transcript can be inserted into the current field; otherwise it is returned to Shortcuts, copied, or saved as a note depending on the action.

Wispr's App Store listing also says keyboard-started dictations show a live Dynamic Island/Lock Screen timer. That is a visible recording indicator and evidence of main-app/ActivityKit participation, not evidence that the keyboard process owns audio.

Wispr's [Data Controls](https://wisprflow.ai/data-controls) says transcription always occurs in the cloud. Privacy Mode controls training/evaluation use; Private Cloud Sync separately controls server storage. With Privacy Mode on and Cloud Sync off, Wispr describes zero server retention. Its [retry documentation](https://docs.wisprflow.ai/articles/2503460374-retry-failed-transcriptions) separately says iOS audio may be saved locally for retry, so “zero cloud retention” should not be confused with “nothing ever written to the device.”

### Strongly inferred session flow

1. The keyboard creates a session/request in storage shared with Flow.
2. If the Flow app is not already able to record, the keyboard initiates the documented handoff to Flow.
3. Flow requests/uses microphone permission, starts a real audio session, and moves to the background after the user swipes or the product returns through an app-specific path.
4. Flow streams or uploads the audio to Wispr's cloud and updates recording/transcription state.
5. The keyboard observes state/results through same-team IPC or polling and inserts final text with `UITextDocumentProxy`.
6. Live Activity/Dynamic Island UI communicates the ongoing recording even when the app is not foreground.

### Unknown

- The keyboard-to-app launch primitive and whether it is documented, specially reviewed, or an implementation detail.
- The App Group identifier and whether coordination uses files, `UserDefaults`, Darwin notifications, sockets, or another mechanism.
- Whether audio upload begins live or after a local segment completes.
- The exact app-specific switchback mechanisms and any special entitlements.

## 4. Typeless: facts and likely architecture

### Proven by Typeless

Typeless's [PiP guide](https://www.typeless.com/help/release-notes/ios/picture-in-picture) is the decisive source. Version 1.9 introduced “Skip app switching” using Picture in Picture. Its steps are:

1. Enable Skip app switching in the containing app and choose Picture in Picture.
2. Drag the Typeless PiP presentation off the left or right edge so it remains tucked away.
3. Open a text field, display the Typeless keyboard, and tap Speak; Typeless says the microphone turns on only while speaking.

Typeless's [iOS release notes](https://www.typeless.com/help/release-notes/ios) also say recording can continue when the keyboard closes or the user changes apps, and the user later returns to the text field/keyboard to finish. This independently shows that the audio session outlives the keyboard UI and belongs to another process.

The two supplied screenshots show:

- A voice-oriented pane and a full typing pane within one Typeless keyboard.
- The same small chevron attached to the right screen edge in both panes.

**Strong visual inference:** that chevron is the handle for the PiP surface the user has dragged off-screen, matching Typeless's own setup instruction. The voice/type swipe changes only the keyboard extension's presentation; the off-screen containing app remains the microphone-capable participant.

Typeless's [current privacy policy](https://www.typeless.com/privacy) says audio and contextual information are processed in real time on cloud servers and discarded after the transcription returns, with third-party providers configured for zero retention. The [App Store listing](https://apps.apple.com/us/app/typeless-ai-voice-keyboard/id6749257650) describes this more precisely as zero *cloud* retention and on-device history. An older release note's statement that everything stays local conflicts with the current detailed policy; it should not be read as evidence of on-device recognition.

### Strongly inferred session flow

1. The user explicitly prepares Typeless's containing app in PiP and tucks it off-screen.
2. PiP keeps the containing app participating in an Apple-managed media/background mode.
3. A tap in the keyboard writes a start/stop request through shared storage or same-team IPC.
4. The containing app activates/deactivates its real microphone session on demand and sends audio for cloud processing.
5. The result returns to shared state and the keyboard inserts it through the text proxy.

This is the closest public competitor match to BuddyGrammar's current architecture.

### Unknown

- Whether Typeless requires Allow Full Access. No current first-party Typeless iOS setup page found in this research states it. Cloud processing proves some process has network access, but that process could be the containing app; public evidence does not identify which target performs networking.
- Its PiP content-source type, audio-session categories, background-mode declarations, App Group identifier, IPC transport, or state machine.
- Whether its normal non-PiP fallback uses a supported URL route or an implementation detail.
- Whether Apple gave Typeless review guidance or an exception. App Store presence alone cannot answer this.

## 5. PiP is proven competitor behavior, but not a documented dictation API

Apple describes [`AVPictureInPictureController`](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller) as a controller for user-initiated video playback in a floating window. Apple's [custom-player PiP guide](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-custom-player) uses `AVPlayerLayer` or `AVSampleBufferDisplayLayer`, requires the media background mode, and warns that PiP must start from user interaction. Apple separately documents PiP for [video calls](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-for-video-calls).

Apple does not document “keep a dictation app available for keyboard IPC” as a PiP use. [App Review Guidelines 2.5.1 and 2.5.4](https://developer.apple.com/app-store/review/guidelines/) require public APIs and background services to be used for their intended purposes. Guideline 2.5.14 also requires a clear visual or audible indication whenever an app records microphone/user activity.

So the accurate conclusion is narrower than “PiP is safe because Typeless does it”:

- **Proven:** Typeless explicitly ships and documents PiP for skip-app-switching voice dictation.
- **Proven:** the technique is technically possible and currently distributed by Apple.
- **Not proven:** Apple considers an arbitrary synthetic PiP keepalive a generally documented or reusable dictation architecture.
- **Risk:** a new implementation remains exposed to App Review interpretation and future platform changes, particularly if the PiP content is not genuine video playback or a video call.

## 6. Modern App Intents explain system entry points, not the keyboard mic

iOS 18 introduced [`AudioRecordingIntent`](https://developer.apple.com/documentation/appintents/audiorecordingintent). It tells the system an intent changes recording state, causes a recording indicator, and requires a Live Activity for the duration of recording. [`LiveActivityIntent`](https://developer.apple.com/documentation/appintents/liveactivityintent) can cause the system to launch an app process in the background without opening the app UI. These APIs are a good explanation for Wispr's documented Action Button, Control Center, widget, Siri, and Shortcut start/stop paths.

They do not prove a custom keyboard can route its own button into the containing app. BuddyGrammar's no-audio experiment documented in [`apple-keyboard-workarounds.md`](apple-keyboard-workarounds.md) found that a shared `Button(intent:)` invoked from the keyboard on iOS 26.5 executed in the **keyboard extension process**, where the microphone restriction still applies.

The iOS 27 beta adds [`allowedExecutionTargets`](https://developer.apple.com/documentation/appintents/appintent/allowedexecutiontargets), allowing an intent to request the main app, App Intents extension, or widget-extension process. This is the first public process-routing primitive that could alter the experiment, but it is beta, untested for this keyboard use case, and does not override App Review guideline 4.4.1. It is a future prototype candidate, not an explanation for the currently shipping iOS 18–26 behavior.

## 7. Mapping to BuddyGrammar

BuddyGrammar already implements both competitor patterns:

| Concern | BuddyGrammar today | Closest public competitor evidence |
| --- | --- | --- |
| Extension microphone | None; main app records | Required by Apple's sandbox; both products' behavior is consistent |
| Ready off-screen process | `AVSampleBufferDisplayLayer`-backed PiP companion in `DictationCompanionController.swift` | Typeless explicitly documents off-screen PiP |
| Start/stop IPC | Darwin notification with App Group session as source of truth in `DictationCompanionBridge.swift` | Likely for both; vendor transport is unknown |
| Shared session/result | App Group preferences/session state | Likely for both; exact vendor format unknown |
| Cold fallback | `buddygrammar://dictation` via responder-chain `openURL:` | Wispr explicitly documents launching its app, but not how |
| Final insertion | Poll session then call keyboard insertion through `UITextDocumentProxy` | Apple-documented keyboard capability; both vendors advertise direct insertion |
| Recording visibility | PiP status surface | Typeless PiP; Wispr Live Activity/Dynamic Island timer |

Specific source landmarks:

- `BuddyGrammarIOS/Features/Companion/DictationCompanionController.swift` creates a sample-buffer PiP controller and calls it an off-screen keepalive.
- `BuddyGrammarKit/Sources/BuddyGrammarKit/DictationCompanionBridge.swift` sends payload-free Darwin signals and uses the App Group session as source of truth.
- `BuddyGrammarKeyboard/KeyboardModel.swift` posts start/stop signals when the companion heartbeat is alive, otherwise deep-links into the app, polls shared session state, and inserts the result.
- `BuddyGrammarKeyboard/KeyboardViewController.swift` walks the responder chain and performs `openURL:` dynamically.

The competitor research therefore validates that BuddyGrammar independently arrived at the same **technical** split used by leading products. It does not resolve the two policy risks already identified in the earlier report:

1. synthetic PiP as a general keepalive is outside Apple's documented playback/video-call scenarios;
2. responder-chain app launching conflicts with Apple's documented extension restrictions and keyboard guideline.

## 8. Practical conclusions for BuddyGrammar

1. Do not search for an in-keyboard microphone entitlement. It does not exist in public Apple documentation, and competitor sources affirm containing-app participation.
2. Treat the supplied Typeless UI as **voice and typing states inside one keyboard extension**, with an off-screen PiP companion—not as two privileged keyboard targets.
3. Full Access is useful for networking and shared state, but never describe it as granting microphone permission. The main app asks for microphone permission separately.
4. Wispr's current route is the clearest non-PiP comparison: accept a visible containing-app launch and manual back gesture, then keep genuine recording active in the background. Its polished automatic return for known apps is not a generic public API.
5. Typeless demonstrates commercial viability of the PiP technique today, but it does not eliminate App Review or forward-compatibility risk for BuddyGrammar.
6. Keep App Intents/Live Activities as system entry points and retest iOS 27 main-process routing when the final SDK is available. Do not assume `Button(intent:)` from the keyboard solves iOS 18–26.
7. If BuddyGrammar needs a durable App-Store-safe design today, the conclusions in [`apple-keyboard-workarounds.md`](apple-keyboard-workarounds.md) remain unchanged: Apple system dictation plus explicit polish is the cleanest same-field path; BuddyGrammar-owned recognition requires a real main-app recording session and honest UX around the handoff.

## Bottom line

The “direct keyboard dictation” is an interaction illusion assembled from two processes:

```text
host app text field
        ↕ UITextDocumentProxy
custom keyboard extension ── shared state / IPC ── containing app
        UI + insertion                           microphone + cloud ASR
                                                        ↕
                                          background audio / PiP / Live Activity
```

Wispr makes the process boundary visible when it must; Typeless hides it behind a prepared off-screen PiP window. Neither product overturns Apple's microphone restriction, and neither publishes a secret general-purpose handoff API.
