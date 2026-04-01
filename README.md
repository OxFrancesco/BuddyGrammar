# BuddyGrammar

BuddyGrammar is a native macOS menu bar utility that rewrites the currently selected text through OpenRouter using `openai/gpt-5.4-nano`.

## Features

- Global hotkeys per prompt profile
- Built-in Grammar profile enabled by default
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
4. Use the default Grammar shortcut `^⌥G` on selected text.
