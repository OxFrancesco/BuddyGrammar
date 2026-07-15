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
    @State private var acceptsCloudProcessing: Bool

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
        _acceptsCloudProcessing = State(
            initialValue: model.settings.hasAcceptedCloudProcessing
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
                Text("Word correction uses the on-device dictionary and keyboard-aware typo matching. After a ★ correction, Undo stays visible for this duration.")
            }

            Section {
                Toggle(isOn: quickDictationBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Skip app switching")
                        Text("Keep BuddyGrammar ready in a small Picture in Picture window so the keyboard mic starts instantly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.quickDictation")
            } header: {
                Text("Quick dictation")
            } footer: {
                Text("After enabling, leave the app so the companion window appears, then drag it off the screen edge to tuck it away. The microphone turns on only when you start dictation from the keyboard. If iOS closes the window, the keyboard falls back to opening the app.")
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

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
                .accessibilityIdentifier("settings.privacyPolicy")
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
                        acceptsCloudProcessing: acceptsCloudProcessing
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
    }

    private var quickDictationBinding: Binding<Bool> {
        Binding(
            get: { model.settings.enablesQuickDictation },
            set: { model.setQuickDictation(enabled: $0) }
        )
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
        acceptsCloudProcessing = settings.hasAcceptedCloudProcessing
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Last updated July 15, 2026")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                policySection(
                    title: "What stays on your device",
                    text: "Normal keyboard input is not sent anywhere. BuddyGrammar stores learned vocabulary and context frequency counts locally to personalize suggestions and predictions. Provider API keys are never included in the app or keyboard. The latest raw transcript and final text are stored locally until you clear them. A separate keyboard handoff copy expires after 24 hours or is removed after insertion. BuddyGrammar has no advertising or analytics SDKs."
                )

                policySection(
                    title: "Star corrections",
                    text: "When you tap ★ after allowing cloud processing, the selected text or current sentence, your correction instruction, and model choice are sent through the BuddyGrammar service to OpenRouter. If on-device handwriting recognition cannot read a drawing, BuddyGrammar can send a normalized black-and-white image of those strokes to the same model as a fallback. OpenRouter and the selected model provider process this content to return the result. BuddyGrammar requests zero-data-retention routing from OpenRouter."
                )

                policySection(
                    title: "Speech to text",
                    text: "When you stop a recording in the BuddyGrammar app, its audio is sent through the BuddyGrammar service to ElevenLabs. If the first transcription request fails, BuddyGrammar retries it once. ElevenLabs returns a transcript. If automatic correction is enabled, that transcript is then sent to OpenRouter. The final text is copied to your clipboard. The temporary recording file is deleted from this device after the request completes. Apple does not permit microphone recording inside a custom keyboard."
                )

                policySection(
                    title: "Accounts, retention, and deletion",
                    text: "The BuddyGrammar service forwards correction text and audio only to provide the requested feature and does not intentionally log or store that content. Provider retention depends on the configured OpenRouter and ElevenLabs account settings and the model provider selected by OpenRouter. ElevenLabs may retain submitted audio and transcripts unless zero-retention mode is enabled for the service account. You can revoke cloud consent and clear the locally saved dictation in the app."
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
