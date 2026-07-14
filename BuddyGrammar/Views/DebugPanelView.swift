import SwiftUI

#if DEBUG
struct DebugPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    debugCard("Runtime", systemImage: "gauge.with.dots.needle.67percent") {
                        debugRow("Status", model.rewriteCoordinator.statusMessage)
                        debugRow("Recording", model.voiceInputCoordinator.isRecording ? "Yes" : "No")
                        debugRow("Processing", model.rewriteCoordinator.isProcessing ? "Yes" : "No")
                        debugRow("Menu phase", model.menuBarStatus.phase.title.isEmpty ? "Idle" : model.menuBarStatus.phase.title)
                    }

                    debugCard("Permissions", systemImage: "lock.shield") {
                        stateRow("Accessibility", model.accessibilityGranted)
                        debugRow("Microphone", model.microphonePermission.title)
                        debugRow("Speech", model.speechRecognitionPermission.title)
                        Button("Refresh") {
                            model.refreshEnvironmentState()
                            model.refreshVoiceSpeechAvailability()
                        }
                        .buttonStyle(NeoBrutalistButton(isPrimary: false))
                    }

                    debugCard("Rewrite", systemImage: "wand.and.stars") {
                        debugRow("Output", model.settingsStore.appSettings.outputMode.title)
                        debugRow("Provider", model.currentProviderDescription)
                        debugRow("API key", model.hasAPIKey ? "Saved" : "Missing")
                        if let error = model.rewriteCoordinator.lastErrorMessage {
                            errorText(error)
                        }
                    }

                    debugCard("Local Models", systemImage: "cpu") {
                        ForEach(LocalModelID.allCases) { modelID in
                            let status = model.localModelStore.status(for: modelID)
                            debugRow(modelID.title, statusLabel(status))
                        }
                        if let error = model.localModelStore.lastErrorMessage {
                            errorText(error)
                        }
                    }

                    debugCard("Voice", systemImage: "mic.fill") {
                        debugRow("Locale", model.voiceLocaleIdentifier)
                        debugRow("Speech required", model.speechRecognitionRequiredForDictation ? "Yes" : "No")
                        debugRow("Fallback", model.voiceFallbackStatus.state.title)
                        if let error = model.voiceModelStore.lastErrorMessage {
                            errorText(error)
                        }
                    }

                    debugCard("Shortcuts", systemImage: "keyboard") {
                        debugRow("Profiles", "\(model.settingsStore.enabledProfilesWithHotkeys().count)")
                        debugRow("Notes", "\(model.notesStore.notesWithHotkeys().count)")
                        debugRow("Dictation", model.voiceHotkey?.displayString ?? "None")
                    }

                    debugCard("Storage", systemImage: "externaldrive") {
                        debugRow("Notes", "\(model.notesStore.notes.count)")
                        debugRow("Profiles", "\(model.settingsStore.profiles.count)")
                        debugRow("Bundle", Bundle.main.bundleIdentifier ?? "Unknown")
                        debugRow("Version", model.appUpdateService.currentVersionDescription)
                    }

                    debugCard("Paths", systemImage: "folder") {
                        debugRow("DerivedData", model.isRunningFromDerivedData ? "Yes" : "No")
                        Text(model.appBundlePath)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(NeoTheme.mutedForeground)
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                }
            }
            .padding(22)
        }
        .background(NeoTheme.background)
        .foregroundStyle(NeoTheme.foreground)
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 14, alignment: .top)
        ]
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            debugHeaderLayout(axis: .horizontal)
            debugHeaderLayout(axis: .vertical)
        }
    }

    private func debugHeaderLayout(axis: Axis) -> some View {
        let isHorizontal = axis == .horizontal

        return Group {
            if isHorizontal {
                HStack(alignment: .center, spacing: 12) {
                    headerTitle
                    Spacer()
                    headerActions
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    headerTitle
                    headerActions
                }
            }
        }
    }

    private var headerTitle: some View {
        HStack(spacing: 8) {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(NeoTheme.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Debug")
                    .font(.system(size: 22, weight: .black, design: .rounded))
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            Button {
                model.copyDebugDiagnostics()
            } label: {
                NeoIconButtonLabel("Copy Diagnostics", systemImage: "doc.on.doc")
            }
            .buttonStyle(NeoBrutalistButton())

            Button {
                model.revealCurrentAppInFinder()
            } label: {
                NeoIconButtonLabel("Reveal App", systemImage: "app.dashed")
            }
            .buttonStyle(NeoBrutalistButton(isPrimary: false))

            Button {
                model.openAppSupportFolder()
            } label: {
                NeoIconButtonLabel("App Support", systemImage: "folder")
            }
            .buttonStyle(NeoBrutalistButton(isPrimary: false))
        }
    }

    private func debugCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NeoTheme.primary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .modifier(NeoBrutalistCard())
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(NeoTheme.mutedForeground)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private func stateRow(_ label: String, _ isOn: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(NeoTheme.mutedForeground)
                .frame(width: 96, alignment: .leading)
            Image(systemName: isOn ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isOn ? NeoTheme.green : NeoTheme.orange)
            Text(isOn ? "Granted" : "Missing")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }

    private func errorText(_ error: String) -> some View {
        Text(error)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(NeoTheme.destructive)
            .textSelection(.enabled)
    }

    private func statusLabel(_ status: LocalModelStatus) -> String {
        if let progress = status.progress {
            return "\(status.state.title) \(Int(progress * 100))%"
        }
        return status.state.title
    }
}
#endif
