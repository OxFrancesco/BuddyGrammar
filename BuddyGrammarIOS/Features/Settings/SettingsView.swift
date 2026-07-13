import BuddyGrammarKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var model: IOSAppModel
    @Environment(\.openURL) private var openURL

    @State private var modelID: String
    @State private var correctionInstruction: String
    @State private var autoCorrectDictation: Bool
    @State private var acceptsCloudProcessing: Bool

    init(model: IOSAppModel) {
        self.model = model
        _modelID = State(initialValue: model.settings.openRouterModelID)
        _correctionInstruction = State(initialValue: model.settings.correctionInstruction)
        _autoCorrectDictation = State(initialValue: model.settings.autoCorrectDictation)
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
                TextField("OpenRouter model", text: $modelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.modelID")

                TextField("Instructions", text: $correctionInstruction, axis: .vertical)
                    .lineLimit(5...9)
                    .accessibilityIdentifier("settings.correctionPrompt")

                Toggle("Correct dictation automatically", isOn: $autoCorrectDictation)
                    .accessibilityIdentifier("settings.autoCorrectDictation")
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
                        correctionInstruction: correctionInstruction,
                        autoCorrectDictation: autoCorrectDictation,
                        acceptsCloudProcessing: acceptsCloudProcessing
                    )
                }
            }

            Section {
                Button("Open BuddyGrammar Settings", systemImage: "gearshape") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                Text("Then open Keyboards, add BuddyGrammar, and enable Allow Full Access for star corrections. Apple requires you to enable this toggle manually.")
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
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Last updated July 13, 2026")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                policySection(
                    title: "What stays on your device",
                    text: "Normal keyboard input is not sent anywhere. Provider API keys are never included in the app or keyboard. A dictated transcript is kept in the app’s shared container until you insert or clear it, and is discarded when next read after 24 hours. BuddyGrammar has no advertising or analytics SDKs."
                )

                policySection(
                    title: "Star corrections",
                    text: "When you tap ★ after allowing cloud processing, the selected text or current sentence, your correction instruction, and model choice are sent through the BuddyGrammar service to OpenRouter. OpenRouter and the selected model provider process this content to return the correction. BuddyGrammar requests zero-data-retention routing from OpenRouter."
                )

                policySection(
                    title: "Speech to text",
                    text: "When you stop a recording in the BuddyGrammar app, its audio is sent through the BuddyGrammar service to ElevenLabs. ElevenLabs returns a transcript. If automatic correction is enabled, that transcript is then sent to OpenRouter. The temporary recording file is deleted from this device after the request completes. Apple does not permit microphone recording inside a custom keyboard."
                )

                policySection(
                    title: "Accounts, retention, and deletion",
                    text: "The BuddyGrammar service forwards correction text and audio only to provide the requested feature and does not intentionally log or store that content. Provider retention depends on the configured OpenRouter and ElevenLabs account settings and the model provider selected by OpenRouter. ElevenLabs may retain submitted audio and transcripts unless zero-retention mode is enabled for the service account. You can revoke cloud consent and clear the pending transcript in Settings."
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
