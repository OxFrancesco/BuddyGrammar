# BuddyGrammar for Android

The Android app mirrors the BuddyGrammar iOS experience with a system keyboard, ★ correction, and ElevenLabs speech-to-text.

## Requirements

- Android Studio with JDK 17+
- Android SDK 36
- Android 8.0 (API 26) or later on the target device

Provider credentials are intentionally absent from this project. The app and IME call the BuddyGrammar Cloudflare Worker, which securely supplies the OpenRouter and ElevenLabs credentials.

## Build and test

```sh
./gradlew testDebugUnitTest lintDebug assembleDebug
./gradlew connectedDebugAndroidTest
```

The debug APK is written to `app/build/outputs/apk/debug/app-debug.apk`.

## Enable the keyboard

1. Install and open BuddyGrammar.
2. Accept the explicit cloud-processing consent during onboarding.
3. Tap **Enable BuddyGrammar keyboard** and enable it in Android settings.
4. Return to BuddyGrammar and tap **Choose BuddyGrammar now**.
5. Open **Keyboard Lab** and focus the sample field.

The keyboard provides normal letter and symbol layouts, shift, delete, globe, space, and return controls. Tap ★ to correct selected text or the current sentence around the cursor. The mic key inserts the most recent app dictation saved within 24 hours.

## Privacy behavior

- Text is sent only after ★ is tapped.
- Audio is sent only after the user stops an app recording.
- Password and other secure input fields disable cloud correction and transcript insertion.
- Language-scoped vocabulary and context frequency counts stay on device to personalize suggestions.
- No app data is included in Android cloud backup or device transfer.
- A correction is discarded if the underlying editor text changes before the response arrives.

## Release distribution

The repository currently produces a locally signed debug APK. Google Play distribution will require the user's Play Console account, release keystore, store listing, and app-signing setup; none of those credentials are committed to the repository.
