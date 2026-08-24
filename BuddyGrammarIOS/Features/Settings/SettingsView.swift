import BuddyGrammarKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var model: IOSAppModel
    @Environment(\.openURL) private var openURL

    @State private var modelID: String
    @State private var usesAutomaticModelUpdates: Bool
    @State private var correctionInstruction: String
    @State private var autoCorrectDictation: Bool
    @State private var automaticallyCorrectWords: Bool
    @State private var correctionUndoDuration: TimeInterval
    @State private var adaptiveTypingEnabled: Bool
    @State private var personalizedPracticeEnabled: Bool
    @State private var acceptsCloudProcessing: Bool
    @State private var copiesCompletedDictationToClipboard: Bool
    @State private var quickDictationDuration: QuickDictationDuration
    @State private var showsLearningResetOptions = false

    init(model: IOSAppModel) {
        self.model = model
        _modelID = State(initialValue: model.settings.openRouterModelID)
        _usesAutomaticModelUpdates = State(
            initialValue: model.settings.usesAutomaticModelUpdates
        )
        _correctionInstruction = State(initialValue: model.settings.correctionInstruction)
        _autoCorrectDictation = State(initialValue: model.settings.autoCorrectDictation)
        _automaticallyCorrectWords = State(
            initialValue: model.settings.automaticallyCorrectWords
        )
        _correctionUndoDuration = State(
            initialValue: model.settings.correctionUndoDuration
        )
        _adaptiveTypingEnabled = State(
            initialValue: model.settings.adaptiveTypingEnabled
        )
        _personalizedPracticeEnabled = State(
            initialValue: model.settings.personalizedPracticeEnabled
        )
        _acceptsCloudProcessing = State(
            initialValue: model.settings.hasAcceptedCloudProcessing
        )
        _copiesCompletedDictationToClipboard = State(
            initialValue: model.settings.copiesCompletedDictationToClipboard
        )
        _quickDictationDuration = State(
            initialValue: model.settings.quickDictationDuration
        )
    }

    var body: some View {
        Form {
            Section {
                Label("Managed securely by BuddyGrammar", systemImage: "lock.shield.fill")
                Text("OpenRouter and ElevenLabs credentials stay on the BuddyGrammar service. You never need to enter or store an API key on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Cloud service")
            } footer: {
                Text("Normal typing stays on-device. The service is contacted only for ★ corrections and dictation that you request.")
            }

            Section("Correction") {
                Toggle(
                    "Update correction model automatically",
                    isOn: $usesAutomaticModelUpdates
                )
                .accessibilityIdentifier("settings.automaticModelUpdates")

                if usesAutomaticModelUpdates {
                    LabeledContent(
                        "Active model",
                        value: BuddyGrammarConfiguration.defaultOpenRouterModelID
                    )
                    .accessibilityIdentifier("settings.activeModel")
                    Text("BuddyGrammar will move to the current recommended model when the app is updated.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("OpenRouter model", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.modelID")
                }

                TextField("Instructions", text: $correctionInstruction, axis: .vertical)
                    .lineLimit(5...9)
                    .accessibilityIdentifier("settings.correctionPrompt")

                Toggle("Correct dictation automatically", isOn: $autoCorrectDictation)
                    .accessibilityIdentifier("settings.autoCorrectDictation")
            }

            Section {
                Toggle("Correct words while typing", isOn: $automaticallyCorrectWords)
                    .accessibilityIdentifier("settings.automaticallyCorrectWords")

                Toggle("Adapt key hit areas", isOn: $adaptiveTypingEnabled)
                    .accessibilityIdentifier("settings.adaptiveTyping")

                Toggle("Personalize practice", isOn: $personalizedPracticeEnabled)
                    .accessibilityIdentifier("settings.personalizedPractice")

                Stepper(
                    value: $correctionUndoDuration,
                    in: 1...10,
                    step: 1
                ) {
                    LabeledContent(
                        "Star undo window",
                        value: undoDurationLabel
                    )
                }
                .accessibilityIdentifier("settings.correctionUndoDuration")
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Adaptive hit areas and practice mastery stay on-device. Key labels and layout never move. After a ★ correction, Undo stays visible for this duration.")
            }

            Section {
                Toggle(
                    "Dynamic Island readiness",
                    isOn: Binding(
                        get: { model.settings.enablesQuickDictation },
                        set: { enabled in
                            Task {
                                await model.setQuickDictation(
                                    enabled: enabled,
                                    duration: quickDictationDuration
                                )
                            }
                        }
                    )
                )
                .accessibilityIdentifier("settings.quickDictation")

                Picker("Keep ready", selection: $quickDictationDuration) {
                    Text("For 5 minutes").tag(QuickDictationDuration.fiveMinutes)
                    Text("For 12 hours").tag(QuickDictationDuration.twelveHours)
                    Text("Always").tag(QuickDictationDuration.always)
                }
                .accessibilityIdentifier("settings.quickDictationDuration")
                .onChange(of: quickDictationDuration) { _, duration in
                    guard model.settings.enablesQuickDictation else { return }
                    Task {
                        await model.setQuickDictation(enabled: true, duration: duration)
                    }
                }

                Label(
                    model.settings.enablesQuickDictation
                        ? "Ready in Dynamic Island"
                        : "Keyboard dictation opens BuddyGrammar first",
                    systemImage: model.settings.enablesQuickDictation
                        ? "waveform.circle.fill"
                        : "arrow.up.forward.app"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.quickDictationStatus")
            } header: {
                Text("Keyboard dictation")
            } footer: {
                Text("Apple does not permit microphone recording inside a custom keyboard, so the keyboard mic normally opens BuddyGrammar to start recording — swipe back and keep talking while the Dynamic Island shows the session. If you enable readiness, BuddyGrammar instead keeps an audio-input session active for the selected period so a keyboard mic tap starts instantly without switching apps. Audio received while waiting is discarded in memory and never written, transcribed, or uploaded. iOS shows microphone and Live Activity indicators, and readiness uses additional battery.")
            }

            Section {
                Toggle(isOn: $acceptsCloudProcessing) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Allow cloud processing")
                        Text("Send text to OpenRouter and recordings to ElevenLabs only when you request those features.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.cloudConsent")

                Toggle(isOn: $copiesCompletedDictationToClipboard) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Copy completed dictation")
                        Text("Opt in to placing each finished transcript on the system clipboard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.copyCompletedDictation")

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
                .accessibilityIdentifier("settings.privacyPolicy")

                Button("Reset on-device learning", systemImage: "trash", role: .destructive) {
                    showsLearningResetOptions = true
                }
                .accessibilityIdentifier("settings.resetLearning")
            } header: {
                Text("Privacy")
            }

            Section {
                Button("Save preferences", systemImage: "checkmark.circle.fill") {
                    model.updateSettings(
                        modelID: modelID,
                        usesAutomaticModelUpdates: usesAutomaticModelUpdates,
                        correctionInstruction: correctionInstruction,
                        autoCorrectDictation: autoCorrectDictation,
                        automaticallyCorrectWords: automaticallyCorrectWords,
                        correctionUndoDuration: correctionUndoDuration,
                        adaptiveTypingEnabled: adaptiveTypingEnabled,
                        personalizedPracticeEnabled: personalizedPracticeEnabled,
                        acceptsCloudProcessing: acceptsCloudProcessing,
                        copiesCompletedDictationToClipboard: copiesCompletedDictationToClipboard
                    )
                }
            }

            Section {
                Button("Open BuddyGrammar Settings", systemImage: "gearshape") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                Text("Then open Keyboards, add BuddyGrammar, and enable Allow Full Access for star corrections and AI handwriting fallback. Apple requires you to enable this toggle manually.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Keyboard setup")
            }

            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier("settings.screen")
        .onChange(of: model.settings, initial: true) { _, settings in
            synchronizeDraft(with: settings)
        }
        .confirmationDialog(
            "Choose what to reset",
            isPresented: $showsLearningResetOptions,
            titleVisibility: .visible
        ) {
            Button("Touch calibration", role: .destructive) {
                model.resetAdaptiveLearning(.typing)
            }
            Button("Learned words", role: .destructive) {
                model.resetAdaptiveLearning(.language)
            }
            Button("Practice history", role: .destructive) {
                model.resetAdaptiveLearning(.practice)
            }
            Button("Reset everything", role: .destructive) {
                model.resetAdaptiveLearning(.all)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes local aggregates. It does not change your keyboard layout or cloud-consent setting.")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var undoDurationLabel: String {
        let seconds = Int(correctionUndoDuration.rounded())
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private func synchronizeDraft(with settings: BuddyGrammarSettings) {
        modelID = settings.openRouterModelID
        usesAutomaticModelUpdates = settings.usesAutomaticModelUpdates
        correctionInstruction = settings.correctionInstruction
        autoCorrectDictation = settings.autoCorrectDictation
        automaticallyCorrectWords = settings.automaticallyCorrectWords
        correctionUndoDuration = settings.correctionUndoDuration
        adaptiveTypingEnabled = settings.adaptiveTypingEnabled
        personalizedPracticeEnabled = settings.personalizedPracticeEnabled
        acceptsCloudProcessing = settings.hasAcceptedCloudProcessing
        copiesCompletedDictationToClipboard = settings.copiesCompletedDictationToClipboard
        quickDictationDuration = settings.quickDictationDuration
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Last updated July 21, 2026")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                policySection(
                    title: "What stays on your device",
                    text: "Normal keyboard input is not sent anywhere. BuddyGrammar stores learned vocabulary, bounded key-offset aggregates, and practice mastery locally to improve typing and choose exercises. It does not retain a readable touch history. During a Lab exercise, the keyboard can read the curated target text for up to 30 minutes; the user’s response is not stored in that session record. Provider API keys are never included in the app or keyboard. The latest raw transcript and final text are stored locally until you clear them. A separate keyboard handoff copy expires after 24 hours or is removed after insertion. BuddyGrammar has no advertising or analytics SDKs."
                )

                policySection(
                    title: "Star corrections",
                    text: "When you tap ★ after allowing cloud processing, the selected text or current sentence, your correction instruction, and model choice are sent through the BuddyGrammar service to OpenRouter. If on-device handwriting recognition cannot read a drawing, BuddyGrammar can send a normalized black-and-white image of those strokes to the same model as a fallback. OpenRouter and the selected model provider process this content to return the result. BuddyGrammar requests zero-data-retention routing from OpenRouter."
                )

                policySection(
                    title: "Speech to text",
                    text: "Apple does not permit microphone recording inside a custom keyboard, so recordings always happen in the BuddyGrammar app. A keyboard dictation visibly opens BuddyGrammar to start recording; the recording can continue while you return to the app you were typing in, with a Live Activity and the iOS microphone indicator showing the session. If you explicitly enable Dynamic Island readiness, the app keeps an audio-input session active for the selected period and discards idle audio in memory without writing, transcribing, or uploading it. Recordings are sent through the BuddyGrammar service to ElevenLabs; a failed request is retried once. If automatic correction is enabled, the transcript is sent to OpenRouter. The final text is copied to your clipboard only if you enable that separate setting, and the temporary recording file is deleted after processing."
                )

                policySection(
                    title: "Accounts, retention, and deletion",
                    text: "The BuddyGrammar service forwards correction text and audio only to provide the requested feature and does not intentionally log or store that content. Provider retention depends on the configured OpenRouter and ElevenLabs account settings and the model provider selected by OpenRouter. ElevenLabs may retain submitted audio and transcripts unless zero-retention mode is enabled for the service account. In Settings, you can revoke cloud consent, clear saved dictation, and reset touch calibration, learned words, practice history, or all on-device learning independently."
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Provider policies")
                        .font(.headline)

                    Link(
                        "OpenRouter privacy and data controls",
                        destination: URL(string: "https://openrouter.ai/docs/guides/privacy/data-collection")!
                    )
                    Link(
                        "ElevenLabs privacy and retention",
                        destination: URL(string: "https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode")!
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("privacyPolicy.screen")
    }

    private func policySection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
