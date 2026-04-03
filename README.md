# BuddyGrammar

BuddyGrammar is a native macOS menu bar utility that rewrites the currently selected text through OpenRouter using `openai/gpt-5.4-nano`.

## Features

- Global hotkeys per personality
- Built-in Standard personality enabled by default
- Starter templates for Formal, Email, Twitter Post, and blank custom personalities
- Replace selection or copy result to the clipboard
- Keychain-backed OpenRouter API key storage
- Accessibility-based text capture with clipboard fallback
- Native menu bar status that shows live rewrite progress

## Project Structure

- `BuddyGrammar/`: app source
- `BuddyGrammarTests/`: unit tests
- `project.yml`: XcodeGen project definition

## Build

Generate the Xcode project:

```bash
xcodegen generate
```

Build:

```bash
xcodebuild -project BuddyGrammar.xcodeproj -scheme BuddyGrammar -configuration Debug -destination 'platform=macOS' build
```

Run tests:

```bash
xcodebuild -project BuddyGrammar.xcodeproj -scheme BuddyGrammar -configuration Debug -destination 'platform=macOS' test
```

## Setup

1. Launch the app.
2. Add your OpenRouter API key in Settings.
3. Grant Accessibility permission in System Settings.
4. Use the default Standard shortcut `⌘⇧1` on selected text.

## Updates

BuddyGrammar now includes Sparkle-based in-app updates backed by GitHub Releases.

- The app reads updates from [`appcast.xml`](./appcast.xml)
- Release builds expose `Check for Updates` in the app UI
- Tagged releases are published through [`.github/workflows/release.yml`](./.github/workflows/release.yml)

### Release Setup

1. Generate or export the Sparkle private key on a trusted Mac:

```bash
/tmp/SparkleToolsBuild/Build/Products/Release/generate_keys -x /tmp/buddygrammar-sparkle-private-key
cat /tmp/buddygrammar-sparkle-private-key
```

2. Save the exported key contents as the GitHub Actions secret `SPARKLE_PRIVATE_KEY`.
3. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in [`project.yml`](./project.yml).
4. Push a tag like `v0.2.0`.

The release workflow builds the app, zips it for Sparkle, uploads it to GitHub Releases, and updates the appcast feed.
