# Apple custom-keyboard dictation without Picture in Picture

Research date: 2026-07-14
Scope: Apple documentation, Apple App Review Guidelines, Apple Developer Forums answers from Apple staff, and the installed Apple SDK. Competitor behavior is treated only as a clue, not as evidence of an API.

## Executive conclusion

Apple still does not permit an iOS custom keyboard extension to access the microphone or speaker. Full Access adds networking and shared-container capabilities; it does not add audio capture. Apple also does not provide a public, App-Store-safe keyboard API for launching the containing app, discovering the host app, returning to that host, or programmatically starting system dictation.

BuddyGrammar's current Picture in Picture companion is therefore not a durable platform solution. Apple's PiP APIs are documented for video playback and video calls, and Apple says PiP should begin only in response to user interaction. A synthetic PiP surface whose purpose is keeping a non-video app alive is also difficult to reconcile with App Review rule 2.5.4, which limits background modes to their intended purposes. The responder-chain `openURL:` route in the keyboard is similarly unsupported and conflicts directly with keyboard rule 4.4.1, which says a keyboard must not launch other apps except Settings.

The best supported shipping design is one keyboard extension with two **UI states**:

1. **Type** — the normal BuddyGrammar keyboard.
2. **Apple Dictation + Polish** — the user invokes Apple's system dictation button, iOS inserts the transcript into the current field, and BuddyGrammar performs an explicit, bounded AI cleanup after the insertion.

This preserves the current app, field, and cursor without PiP, app switching, or extension microphone access. Its tradeoff is that Apple, not BuddyGrammar, performs speech recognition.

A second, higher-friction supported option is an explicitly started **Recording Session** in the containing app. The app records real audio under the audio background mode and exposes an obvious system recording indicator; the keyboard only sends segment/control messages through the shared App Group. It is not an invisible ready state: if the app is not genuinely recording, iOS may suspend it.

The modern SwiftUI `Button(intent:)` theory was tested without audio. An `AudioRecordingIntent` shared through `BuddyGrammarKit` was extracted into both the app's and keyboard extension's App Intent metadata, yet tapping it from the keyboard on iOS 26.5 Simulator ran `perform()` in bundle `com.francescooddo.BuddyGrammar.Keyboard`, process `BuddyGrammarKeyboard`. It did not enter the containing app process. This rules it out as an iOS 18–26 workaround. iOS 27 adds `allowedExecutionTargets = .main`, the first explicit process-routing API for this theory; that future variant still needs SDK/device testing and Apple DTS/App Review clarification.

## What BuddyGrammar does today

The present implementation confirms that the “video thingy” is a PiP keepalive rather than video content:

- `BuddyGrammarIOS/Features/Companion/DictationCompanionController.swift` creates an `AVSampleBufferDisplayLayer`, synthesizes frames, creates `AVPictureInPictureController.ContentSource`, enables automatic inline PiP, marks playback as linear, and sets an audio session category of `.playback`.
- `BuddyGrammarIOS/Support/Info.plist` declares the `audio` background mode.
- `BuddyGrammarKeyboard/KeyboardViewController.swift` sets `hasDictationKey = false`, then uses the responder chain and `NSSelectorFromString("openURL:")` to try to open the containing app.
- `BuddyGrammarKeyboard/Info.plist` requests Full Access.

The direction seen in newer competitor releases—no synthetic video surface, with two apparent keyboard states—is consistent with moving away from PiP. It does not prove that the keyboard itself records audio.

Current competitor documentation supports that interpretation:

- Typeless explicitly calls its panes a **Voice keyboard** and a **full typing keyboard**, switched by swiping left or right ([Typeless iOS release notes](https://www.typeless.com/help/release-notes/ios/swipe-to-type)). That is an internal UI mode switch, not a second audio entitlement.
- Wispr Flow's current iPhone setup still describes enabling and selecting its custom keyboard ([Flow keyboard setup](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone)). Its iOS 26.4 release note says tapping Start Flow now opens Flow and the user must swipe back manually; it also says automatic app-specific styles stopped because iOS removed the host-app-identification behavior Flow had relied on ([Wispr Flow What's New](https://wisprflow.ai/whats-new)). That is evidence of a higher-friction app handoff, not in-keyboard microphone access.

## Non-negotiable Apple platform boundaries

### A custom keyboard cannot record audio

Apple's current [Configuring Open Access for a Custom Keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) documentation lists the base sandbox restrictions, including no microphone or speaker, then says Open Access adds network and shared-container access. Apple's archived but still explicit [Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) guide says custom keyboards have no access to the device microphone and therefore cannot accept dictation. The general [App Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html) also says app extensions cannot access the camera or microphone and cannot perform long-running background tasks.

Consequences:

- Full Access does not unlock the microphone.
- `AVAudioRecorder`, `AVAudioEngine`, or `SFSpeechRecognizer` inside the keyboard cannot be the workaround.
- A second keyboard extension target has the same sandbox restriction.
- A shared App Group can move commands and data, but it cannot lend the containing app's microphone entitlement or process lifetime to the extension.

### A keyboard cannot use a public round trip through the containing app

[App Review Guideline 4.4.1](https://developer.apple.com/app-store/review/guidelines/) requires keyboard extensions to provide keyboard input, provide a next-keyboard control, remain functional without Full Access, and not launch other apps except Settings.

Apple DTS's June 2026 answer in [“Identifying Host Apps in iOS Custom Keyboard Extension”](https://developer.apple.com/forums/thread/826851) is unusually direct:

- there is no public, App-Store-safe API for the keyboard to identify its host app;
- there is no public API for the containing app to identify the original host app;
- code that extracts unpublished implementation details is likely to break;
- developers should file a high-level enhancement request for a keyboard → containing app → original host round trip that does not reveal the host's identity.

That thread explicitly mentions Typeless in a follow-up, but Apple's answer does not reveal or bless a hidden technique. It instead confirms the missing public API. Apple DTS has also said that direct URL opening from extensions and responder/runtime bypasses are unsupported compatibility hazards in [this iOS 18 discussion](https://developer.apple.com/forums/thread/764570). The generic extension guide only documented direct `openURL:` behavior for the old Today widget model, not custom keyboards ([App Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html)).

Apple's [iOS & iPadOS 26.4 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_4-release-notes) do not announce a new custom-keyboard handoff API or document a supported host-app round trip. The timing may explain why products changed behavior, but it is not evidence that Apple officially removed a previously public solution: Apple's current position is that no such public solution exists.

Therefore BuddyGrammar should not depend on `NSSelectorFromString("openURL:")`. Even if it happens to work on a particular OS build, it is neither a supported lifecycle primitive nor App Review-safe.

### PiP is a media feature, not a general keepalive

Apple's [custom-player PiP guide](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-custom-player) describes PiP for video playback using player layers or sample-buffer display layers and warns that PiP must begin in response to user interaction; apps that fail this requirement risk App Review rejection. Apple separately documents PiP for [video calls](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-for-video-calls). `AVPictureInPictureSampleBufferPlaybackDelegate` is explicitly a delegate for [controlling playback](https://developer.apple.com/documentation/avkit/avpictureinpicturesamplebufferplaybackdelegate).

[App Review Guideline 2.5.4](https://developer.apple.com/app-store/review/guidelines/) limits background services to their intended purposes. A generated status card whose material purpose is retaining app execution for dictation is not one of Apple's documented PiP uses. The same rule makes silent playback or inaudible looping audio unsuitable as alternate keepalives.

## Supported design A: Apple Dictation + explicit AI polish

This is the strongest production recommendation because it stays entirely inside documented keyboard and text-input behavior.

### User flow

1. BuddyGrammar remains a useful typing keyboard and sets `hasDictationKey = false`.
2. Where iOS provides its system dictation control, the user taps that Apple-owned mic control. No BuddyGrammar code starts the microphone.
3. iOS inserts recognized text into the current host field.
4. The keyboard observes ordinary text changes, conservatively identifies the newly inserted range from a snapshot, and offers **Polish**.
5. Only after an explicit tap, BuddyGrammar sends the bounded inserted text for AI processing and replaces that same safe range through `UITextDocumentProxy`.

Apple documents `hasDictationKey` as a flag that disables the system dictation key when a custom keyboard supplies its own dictation UI ([`hasDictationKey`](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/hasdictationkey)). Apple's [custom keyboard interface guide](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface) notes that iOS can show the system dictation button in some configurations, and a custom keyboard that implements dictation should set the flag to avoid two dictation buttons. Keeping the flag `false` is therefore correct for a design that relies on Apple's button.

Apple's text-input system inserts dictation output into the current text view ([`UITextInput`](https://developer.apple.com/documentation/uikit/uitextinput)). A custom keyboard receives generic text and selection callbacks and edits through its proxy ([Handling Text Interactions in Custom Keyboards](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards), [`UITextDocumentProxy`](https://developer.apple.com/documentation/uikit/uitextdocumentproxy)). Open Access can be used for server-side analysis if the user has granted it and the app discloses the data use ([Configuring Open Access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)).

### Important limits

- There is no documented custom-keyboard API that starts or stops Apple's dictation.
- The system dictation key is conditional; Apple says it appears only in some cases. Hardware, keyboard configuration, device class, policy, and host field can affect availability.
- Host-side dictation completion methods are part of `UITextInput`; they are not exposed as a reliable dictation-session callback on `UITextDocumentProxy`.
- [`UITextInputContext.isDictationInputExpected`](https://developer.apple.com/documentation/uikit/uitextinputcontext/isdictationinputexpected) is a likelihood/context signal, not a guaranteed “dictation began/ended” event.
- The keyboard cannot assume every observed insertion is dictation. It must compare document identifier, selection, surrounding context, timing, and explicit user state. If the change is ambiguous, do not auto-rewrite it.
- Secure fields and phone-pad fields can replace custom keyboards by design.

For these reasons, **Dictate** should be an instructional/state button that guides the user to Apple's visible mic, while **Polish** is the explicit action BuddyGrammar owns. It must not visually imply that BuddyGrammar's button itself starts recording.

## Supported design B: an explicit real recording session

The containing app may start genuine audio recording while it is foregrounded and continue it under the audio background mode. Apple's [`AVAudioSession.Category.record`](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record) documentation says to declare the audio background mode when recording must continue after the app moves to the background; [`AVAudioRecorder`](https://developer.apple.com/documentation/avfaudio/avaudiorecorder) is a supported recording API. Apple explains that background capabilities should be configured for their actual purpose in [Configuring Background Execution Modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes).

In that design:

- The user explicitly starts **Session Mode** in the app.
- Recording is real, visible, privacy-disclosed, time-bounded, and accompanied by the system microphone indicator.
- The user switches to another app and selects BuddyGrammar.
- The keyboard uses the existing shared App Group/Darwin-notification bridge only to mark segments or request processing.
- The main app transcribes/processes the real stream and shares the result back; the keyboard inserts it through the proxy.
- The user explicitly ends the session.

This avoids PiP, but it does not eliminate the launch/setup step. Once recording stops or the audio session deactivates, iOS can suspend the containing app and keyboard messages are no longer a reliable wake mechanism. A “ready” mode that is not actually recording cannot claim the privileges of background recording. Long sessions also have obvious privacy, battery, thermal, and retention implications.

## Tested current dead end; possible iOS 27 prototype: AudioRecordingIntent + Live Activity

The public building blocks align surprisingly well with the desired UX, but the no-audio spike shows that today's process boundary is the wrong one.

Apple provides:

- SwiftUI [`Button(intent:)`](https://developer.apple.com/documentation/swiftui/button), available from iOS 17, for invoking an App Intent.
- [`AudioRecordingIntent`](https://developer.apple.com/documentation/appintents/audiorecordingintent), available from iOS 18, which identifies an intent that starts, stops, or modifies recording. Apple requires the system recording indicator and, on iOS/iPadOS/watchOS, a Live Activity for the entire recording; otherwise recording stops.
- [`LiveActivityIntent`](https://developer.apple.com/documentation/appintents/liveactivityintent), whose documentation says the system can perform the intent while the app is backgrounded, launch the app process without opening the app, run `perform()`, and start the Live Activity.
- [ActivityKit's Live Activity guide](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), which describes App Intent controls and background Live Activity starts. A real implementation needs the Live Activity setup, including a widget extension and `NSSupportsLiveActivities`.

### Simulator result on iOS 26.5

The dry-run probe shared a public intent type through `BuddyGrammarKit`, exposed it with `Button(intent:)`, conformed it to `AudioRecordingIntent`, and made `perform()` write only process identity to the App Group. It did not create a recorder, configure `AVAudioSession`, request microphone access, or play audio.

Observed evidence:

- The intent and `Button(intent:)` compile for an application extension with the iOS 26.5 SDK.
- Xcode's metadata processor placed `SharedAudioRecordingIntentProbe` in both `BuddyGrammar.app/Metadata.appintents` and `BuddyGrammarKeyboard.appex/Metadata.appintents`.
- Tapping the keyboard button kept the host UI in place and wrote `bundle=com.francescooddo.BuddyGrammar.Keyboard` and `process=BuddyGrammarKeyboard`.
- An extension-local version of the same probe produced the same process identity.
- Microphone permission remained denied throughout the test.

Therefore, even when the intent implementation is present in both products, iOS 26.5 chooses the keyboard extension process. `AudioRecordingIntent` does not transfer execution or microphone capability to the containing app. Adding `LiveActivityIntent` cannot repair that process choice by itself. There is no public process-target selector in the iOS 26.5 SDK.

### Explicit process routing on iOS 27

Apple introduced [`allowedExecutionTargets`](https://developer.apple.com/documentation/appintents/appintent/allowedexecutiontargets) and [`IntentExecutionTargets`](https://developer.apple.com/documentation/appintents/intentexecutiontargets) in the 2027 OS releases. Apple's WWDC26 session [“Discover new capabilities in App Intents”](https://developer.apple.com/videos/play/wwdc2026/345/) explains that an intent can target the main app process, an App Intents extension, or a widget extension. Setting the intent's allowed target to `.main` is the first documented way to express the needed containing-app execution.

That API is not in the installed SDK, so it cannot be compiled or tested in this repository today. Even on iOS 27, Apple has not published an example of a custom keyboard invoking this pattern. Because guideline 4.4.1 separately restricts keyboards from launching apps, obtain written DTS/App Review guidance on whether a system-executed, UI-less recording intent counts as an allowed keyboard interaction before shipping it.

## What “two keyboard modes” most likely means

Apple permits separate keyboard extension targets for different languages and also permits one multilingual keyboard ([Creating a Custom Keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard), archived [Custom Keyboard guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)). That does not create an audio entitlement. [`advanceToNextInputMode()`](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/advancetonextinputmode()) moves to the next input mode chosen by the system; it cannot privately target a companion keyboard.

The safer interpretation is two **internal presentation modes in one extension**, not two privileged extension sandboxes:

- **Type mode**: complete keyboard, globe key, offline baseline.
- **Dictate/Polish mode**: guidance for Apple's dictation button, insertion tracking, explicit processing controls, and a clear fallback when the system button is unavailable.

Each installed keyboard still needs to meet guideline 4.4.1 independently. Creating two feature-only keyboard targets increases onboarding and review complexity without solving microphone access.

## Theory scorecard

| Theory | Platform assessment | Why |
| --- | --- | --- |
| Apple system dictation, then bounded AI polish | **Confirmed documented; recommended** | System owns the microphone, host app and cursor never change, keyboard uses ordinary text proxy APIs. |
| Explicit real recording session started in the app | **Supported, with UX/privacy cost** | Genuine recording can continue under the audio background mode; it cannot be an invisible idle keepalive. |
| `AudioRecordingIntent` + `LiveActivityIntent` from the keyboard | **Rejected for iOS 18–26** | A shared intent present in both metadata bundles executed in the keyboard process on iOS 26.5 Simulator, so the microphone restriction remains. |
| iOS 27 App Intent with execution target `.main` | **Promising future prototype** | Explicit main-process routing exists, but local SDK cannot test it and keyboard-specific review status is unknown. |
| Two keyboard extension targets | **Supported structure, no capability gain** | Both extensions remain microphone-less; switching is system-controlled. |
| `AVAudioEngine` / Speech inside keyboard with Full Access | **Unsupported** | Full Access does not grant microphone access. |
| Responder-chain `openURL:` round trip | **Unsupported; remove dependency** | No public round-trip API and guideline 4.4.1 forbids launching other apps except Settings. |
| Synthetic PiP status card | **Reject as keepalive** | PiP is documented for video playback/calls; background mode use must match its intended purpose. |
| Silent/inaudible audio playback to stay alive | **Reject** | Misuses the audio background mode and has no user-facing audio purpose. |
| PushToTalk framework | **Reject for dictation** | Apple documents [Push to Talk](https://developer.apple.com/documentation/pushtotalk/creating-a-push-to-talk-app) for walkie-talkie-style group communication with channel/system UI, not private dictation capture. |

## Recommended BuddyGrammar sequence

1. Ship the **Type / Apple Dictation + Polish** UI-state design first. Keep `hasDictationKey = false`; make the Apple-owned mic dependency unambiguous; make polish explicit and conservative.
2. Remove the product's dependency on synthetic PiP and responder-chain app opening. Do not replace them with silent audio or another hidden keepalive.
3. If BuddyGrammar's own recognition model is essential, offer an opt-in, visibly active, time-capped **Session Mode** started in the app. Treat it as a recording feature, not “keyboard mic access.”
4. Do not build the iOS 18–26 product flow around App Intent routing; the instrumented no-audio probe executed in the keyboard process.
5. Re-run the shared-intent probe when Xcode 27 is available using the documented `.main` execution target before adding any audio.
6. File Feedback and an Apple DTS question requesting a supported keyboard → containing-app process → keyboard result path that does not identify or relaunch the host app. Reference the high-level need and the limitation described by Apple DTS; do not ask for host-bundle discovery.

## No-audio simulator test plan

These checks deliberately do not activate an audio session, access the microphone, play sound, speak text, or use speech recognition.

### Executed results — Xcode 26.6, iPhone 17 Pro Simulator, iOS 26.5

- The normal keyboard, numbers, symbols, emoji, LaTeX, and handwriting-mode buttons were exercised without drawing or invoking any microphone.
- The Apple-owned system microphone control appeared with BuddyGrammar selected. It was never tapped.
- Temporary builds with `hasDictationKey = false` and `true` rendered the same system microphone control on this Simulator runtime. The source was restored to `false`; do not rely on this property to create a privileged voice mode.
- Six unit tests and two Keyboard Lab UI tests passed.
- The extension-local and shared-package `AudioRecordingIntent` buttons both executed inside `BuddyGrammarKeyboard`. The shared probe was present in both the app and extension App Intent metadata.
- With the companion absent, tapping BuddyGrammar's existing mic button logged `Companion not alive; deep linking`, did not visibly leave Keyboard Lab, and expired the launch session after 15 seconds. This confirms the fallback path was exercised; because Keyboard Lab belongs to the containing app, it is not proof of a supported external-host round trip.
- The containing app's microphone permission stayed denied. No audio session, speech synthesis, recording, or playback was triggered.

### 1. System dictation control ownership

- Use a Face ID iPhone simulator with BuddyGrammar enabled and Full Access both on and off.
- With `hasDictationKey = false`, inspect whether iOS renders its own mic control in ordinary text fields.
- In a temporary development build only, compare the flag with `true`; on iOS 26.5 Simulator it did not suppress the system control.
- Tap only BuddyGrammar's non-audio mode buttons. Do **not** tap the system mic.
- Verify the keyboard remains useful when the Apple mic is unavailable and when Full Access is off.

Pass condition: the UI correctly treats system dictation availability as conditional and never claims that a BuddyGrammar button controls recording.

### 2. Keyboard switching and internal modes

- Verify short tap and long-press behavior of the globe/next-keyboard control.
- Verify **Type** and **Dictate/Polish** are presentation states inside the same keyboard and do not misuse the globe button.
- Move between multiple host fields/apps and confirm mode state is either deliberately reset or restored without treating another insertion as captured dictation.

Pass condition: next-keyboard behavior remains system-standard and both BuddyGrammar modes retain a functional typing path.

### 3. Conservative text-diff behavior

- Snapshot document identifier, selection, and available context when entering Dictate/Polish mode.
- Simulate insertions by typing or pasting text—never by recording—and observe `textWillChange`, `textDidChange`, selection changes, and proxy context.
- Test cursor moves, autocorrection, host-side replacements, paste, undo, field switching, secure fields, and truncated context.
- Ensure an explicit **Polish** replaces only a confidently captured span. Ambiguous changes must cancel capture rather than rewrite surrounding text.

Pass condition: no unrelated user or host text can be sent or replaced because of a guessed dictation boundary.

### 4. App Intent process-routing spike

- Add a development-only, non-audio intent conforming to `LiveActivityIntent`; its `perform()` should write the process name, process identifier, bundle identifier, timestamp, and lifecycle events to unified logging and an App Group file.
- Invoke it from a keyboard `Button(intent:)` while another app owns the text field.
- Do not configure `AVAudioSession` and do not conform the dry run to behavior that begins actual recording.
- Verify whether execution occurs in the keyboard extension, main BuddyGrammar app, or another process; verify whether any UI/app switch occurs.
- If a dry-run Live Activity is started, end it immediately and verify cleanup.
- Repeat after process termination, device lock/unlock where simulator permits, Full Access on/off, and cold/warm app state.

Pass condition for the research spike: evidence identifies the execution process and lifecycle without audio. It is not a production pass unless Apple documents that routing. The `.main` variant must wait for the iOS 27 SDK.

### 5. Removal regression

- Confirm no test path calls `openURL:`, starts PiP, activates `.playback`, or shows a PiP surface.
- Confirm pressing BuddyGrammar UI controls does not leave the host app.

Pass condition: all non-audio UI and text tests operate without PiP, app launch, sound, or microphone activation.

### Device-only follow-up

The simulator cannot validate real microphone privacy indicators, audio interruptions, background recording lifetime, lock-screen behavior, memory pressure, route changes, or App Store review behavior. Test those later on a physical device, in daylight, with an intentionally silent input if desired. The no-audio simulator pass should happen first.

## Feedback request to Apple

Ask for a public mechanism with this shape:

> From a user-initiated control in a custom keyboard, execute a declared recording intent in the containing app process without revealing the current host app, without visually launching the containing app, and return a result to the keyboard through the shared container.

Also ask Apple to clarify:

- whether `Button(intent:)` in a custom keyboard may invoke an `AudioRecordingIntent` / `LiveActivityIntent` implemented by the containing app;
- which process owns the intent on iOS 18–26;
- whether iOS 27 `allowedExecutionTargets = .main` is supported from a custom keyboard;
- how this interaction is interpreted under guideline 4.4.1;
- the supported cancellation, privacy-indicator, and Live Activity lifecycle.

Apple DTS's existing thread notes feedback FB22247647 for host-app identity. BuddyGrammar's request should be broader and privacy-preserving: it does not need the host's identity, only a supported process handoff and result channel.

## Bottom line

There is no hidden “keyboard microphone entitlement” suggested by the competitors' two modes. Today, the clean workaround is to let Apple Dictation own capture and let BuddyGrammar own explicit cleanup. For BuddyGrammar's own speech engine, the only clearly supported current route is a real, user-started recording session in the containing app. The iOS 26.5 App Intent probe stayed inside the keyboard process, so it cannot remove the handoff today. The iOS 27 `.main` variant may change that result, but it still needs instrumented device evidence and written Apple clarification before it can replace the shipping architecture.
